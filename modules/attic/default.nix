# The attic binary cache in a microVM, on the `vms/attic` logical volume. The
# host forwards the cache's port to it, so the LAN reaches the cache at the
# host's address.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.atticVm;
  net = import ./net.nix;
  inherit (config.clan.core.vars.generators) attic-token-key attic-signing uptime-push;
  guest = config.microvm.vms.attic.config.config;
  atticdConfig = (pkgs.formats.toml { }).generate "atticd.toml" guest.services.atticd.settings;
  lanAddress = (lib.head config.networking.interfaces.${cfg.interface}.ipv4.addresses).address;
  gatus = builtins.match "https://([0-9.]+):([0-9]+)" (toString config.diskPush.url);
  gatusIp = lib.elemAt gatus 0;
  gatusPort = lib.elemAt gatus 1;

  # cloud-hypervisor takes no credentials, so the secrets reach the VM as a
  # read-only disk.
  secretsImage = "/run/microvm-attic/secrets.erofs";
  secrets = {
    atticd-env = attic-token-key.files.env.path;
    attic-signing-key = attic-signing.files.key.path;
    uptime-push-token = uptime-push.files.token.path;
  };
in
{
  options.atticVm.interface = lib.mkOption {
    type = lib.types.str;
    example = "eno1";
    description = "Interface the LAN reaches the cache on.";
  };

  config = {
    assertions = [
      {
        assertion = gatus != null;
        message = "modules/attic: diskPush.url must be https://<ip>:<port>, which the VM's firewall rules read.";
      }
    ];

    # Replacing the key revokes every token it signed.
    clan.core.vars.generators.attic-token-key = {
      files.env.secret = true;
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        printf 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=%s\n' \
          "$(openssl genrsa -traditional 4096 | base64 -w0)" > "$out/env"
      '';
    };

    clan.core.vars.generators.attic-signing = {
      files.key.secret = true;
      files.pubkey.secret = false;
      runtimeInputs = [ pkgs.nix ];
      script = ''
        nix --extra-experimental-features nix-command key generate-secret \
          --key-name ${net.cache}-1 > "$out/key"
        nix --extra-experimental-features nix-command key convert-secret-to-public \
          < "$out/key" > "$out/pubkey"
      '';
    };

    # The builder VM's token: pull and push only, so it can neither delete
    # paths nor reconfigure the cache.
    clan.core.vars.generators.attic-push-token = {
      dependencies = [ "attic-token-key" ];
      files.token.deploy = false;
      runtimeInputs = [ pkgs.attic-server ];
      script = ''
        set -a
        . "$in/attic-token-key/env"
        atticadm -f ${atticdConfig} make-token --sub builder --validity 10y \
          --pull ${net.cache} --push ${net.cache} | tr -d '\n' > "$out/token"
      '';
    };

    microvm.vms.attic.config = {
      imports = [ ./guest.nix ];
      attic = {
        secrets = secretsImage;
        apiEndpoint = "http://${lanAddress}:${toString net.port}/";
        gatusUrl = config.diskPush.url;
        gatusPubkey = config.diskPush.pubkeyFile;
      };
    };

    systemd.services.microvm-attic-secrets = {
      description = "Build the attic MicroVM's secrets disk";
      before = [ "microvm@attic.service" ];
      requiredBy = [ "microvm@attic.service" ];
      partOf = [ "microvm@attic.service" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "microvm-attic";
        RuntimeDirectoryMode = "0700";
        UMask = "0077";
        LoadCredential = lib.mapAttrsToList (name: path: "${name}:${path}") secrets;
      };
      script = ''
        ${lib.getExe' pkgs.erofs-utils "mkfs.erofs"} --quiet ${secretsImage} "$CREDENTIALS_DIRECTORY"
        chown -R microvm:kvm "$RUNTIME_DIRECTORY"
      '';
    };

    systemd.services."microvm@attic" = {
      requires = [ "dev-vms-attic.device" ];
      after = [ "dev-vms-attic.device" ];
    };

    services.udev.extraRules = ''
      ENV{DM_VG_NAME}=="vms", ENV{DM_LV_NAME}=="attic", OWNER="microvm", GROUP="kvm", MODE="0600"
    '';

    # The tap only exists while the VM runs, so it gets its address here.
    systemd.services."microvm-tap-interfaces@attic".serviceConfig.ExecStartPost = [
      "${lib.getExe' pkgs.iproute2 "ip"} address add ${net.host}/${toString net.prefixLength} dev ${net.tap}"
      "${lib.getExe' pkgs.procps "sysctl"} -w net.ipv6.conf.${net.tap}.disable_ipv6=1"
    ];

    # No VM here runs a hypervisor of its own.
    boot.extraModprobeConfig = "options kvm_amd nested=0";

    networking.nat = {
      enable = true;
      externalInterface = cfg.interface;
      externalIP = lanAddress;
      forwardPorts = [
        {
          sourcePort = net.port;
          destination = "${net.guest}:${toString net.port}";
          proto = "tcp";
          # The host reaches the cache at the address atticd tells clients.
          loopbackIPs = [ lanAddress ];
        }
      ];
      extraCommands = ''
        iptables -w -t nat -A nixos-nat-post -s ${net.guest} -d ${gatusIp} -p tcp --dport ${gatusPort} -o ${cfg.interface} -j MASQUERADE
      '';
    };

    # The VM may only answer and push to Gatus: no host, pods or services.
    # mangle runs before kube-proxy's DNAT and flannel's FORWARD accepts.
    # A reload runs the stop commands first, so nothing removes the filter.
    # Rules alternate between two chains, and the live one is only removed
    # once the other takes traffic, wherever an earlier run stopped.
    networking.firewall.extraCommands = ''
      mangle="iptables -w -t mangle"
      jump="PREROUTING -i ${net.tap} -j"
      if $mangle -C $jump attic-vm-a 2>/dev/null; then
        live=attic-vm-a next=attic-vm-b
      else
        live=attic-vm-b next=attic-vm-a
      fi
      while $mangle -D $jump $next 2>/dev/null; do :; done
      $mangle -F $next 2>/dev/null || $mangle -N $next
      $mangle -A $next -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
      $mangle -A $next -d ${gatusIp} -p tcp --dport ${gatusPort} -j RETURN
      $mangle -A $next -j DROP
      $mangle -I $jump $next
      while $mangle -D $jump $live 2>/dev/null; do :; done
      $mangle -F $live 2>/dev/null || true
      $mangle -X $live 2>/dev/null || true
    '';
  };
}
