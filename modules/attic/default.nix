# The attic binary cache, in a microVM on gaea, on the `vms/attic` logical
# volume. gaea forwards the cache's port to it, so the LAN reaches the cache at
# gaea's address.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  net = import ./net.nix;
  inherit (config.clan.core.vars.generators) attic-jwt attic-signing uptime-push;
  guest = config.microvm.vms.attic.config.config;
  lanAddress = (lib.head config.networking.interfaces.eno1.ipv4.addresses).address;
  gatus = builtins.match "https://([0-9.]+):([0-9]+)" (toString config.diskPush.url);
  gatusIp = lib.elemAt gatus 0;
  gatusPort = lib.elemAt gatus 1;

  # cloud-hypervisor takes no credentials, so the secrets reach the guest as
  # a read-only disk holding a tar, which ./guest.nix unpacks into /run.
  secretsTar = "/run/microvm-attic/secrets.tar";

  stopVmFilter = ''
    iptables -w -t mangle -D PREROUTING -i ${net.tap} -j attic-vm 2>/dev/null || true
    iptables -w -t mangle -F attic-vm 2>/dev/null || true
    iptables -w -t mangle -X attic-vm 2>/dev/null || true
  '';
in
{
  assertions = [
    {
      assertion = gatus != null;
      message = "modules/attic: diskPush.url must be https://<ip>:<port>, which the VM's firewall rules read.";
    }
  ];

  # A token is a JWT signed with this key, so replacing it revokes every token.
  clan.core.vars.generators.attic-jwt = {
    files.key.secret = true;
    runtimeInputs = [ pkgs.openssl ];
    script = ''
      openssl genrsa -traditional 4096 | base64 -w0 > "$out/key"
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
    dependencies = [ "attic-jwt" ];
    # Nothing on gaea uses it until the builder VM does.
    files.token.deploy = false;
    runtimeInputs = [ pkgs.attic-server ];
    script = ''
      ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=$(<"$in/attic-jwt/key") \
        atticadm -f ${
          (pkgs.formats.toml { }).generate "atticd.toml" guest.services.atticd.settings
        } make-token --sub builder --validity 10y \
        --pull ${net.cache} --push ${net.cache} | tr -d '\n' > "$out/token"
    '';
  };

  microvm.vms.attic.config = {
    imports = [ ./guest.nix ];
    attic = {
      secrets = secretsTar;
      apiEndpoint = "http://${lanAddress}:${toString net.port}/";
      gatusUrl = config.diskPush.url;
      gatusPubkey = config.diskPush.pubkeyFile;
    };
  };

  systemd.services.microvm-attic-secrets = {
    description = "Pack the attic MicroVM's secrets";
    before = [ "microvm@attic.service" ];
    requiredBy = [ "microvm@attic.service" ];
    partOf = [ "microvm@attic.service" ];
    path = [ pkgs.gnutar ];
    serviceConfig = {
      Type = "oneshot";
      RemainAfterExit = true;
      RuntimeDirectory = "microvm-attic";
      RuntimeDirectoryMode = "0700";
      UMask = "0077";
    };
    script = ''
      cd "$RUNTIME_DIRECTORY"
      mkdir staging
      printf 'ATTIC_SERVER_TOKEN_RS256_SECRET_BASE64=%s\n' "$(<${attic-jwt.files.key.path})" > staging/atticd.env
      cp ${attic-signing.files.key.path} staging/signing-key
      cp ${uptime-push.files.token.path} staging/uptime-push-token
      tar --create --file ${secretsTar} --owner=0 --group=0 -C staging .
      rm -r staging
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

  # No VM on gaea runs a hypervisor of its own.
  boot.extraModprobeConfig = "options kvm_amd nested=0";

  networking.nat = {
    enable = true;
    externalInterface = "eno1";
    externalIP = lanAddress;
    forwardPorts = [
      {
        sourcePort = net.port;
        destination = "${net.guest}:${toString net.port}";
        proto = "tcp";
        # gaea reaches the cache at the address atticd tells clients.
        loopbackIPs = [ lanAddress ];
      }
    ];
    extraCommands = ''
      iptables -w -t nat -A nixos-nat-post -s ${net.guest} -d ${gatusIp} -p tcp --dport ${gatusPort} -o eno1 -j MASQUERADE
    '';
  };

  # The VM may only answer and push to Gatus: no gaea, pods or services.
  # mangle runs before kube-proxy's DNAT and flannel's FORWARD accepts.
  networking.firewall.extraCommands = ''
    ${stopVmFilter}
    iptables -w -t mangle -N attic-vm
    iptables -w -t mangle -A attic-vm -m conntrack --ctstate ESTABLISHED,RELATED -j RETURN
    iptables -w -t mangle -A attic-vm -d ${gatusIp} -p tcp --dport ${gatusPort} -j RETURN
    iptables -w -t mangle -A attic-vm -j DROP
    iptables -w -t mangle -A PREROUTING -i ${net.tap} -j attic-vm
  '';
  networking.firewall.extraStopCommands = stopVmFilter;
}
