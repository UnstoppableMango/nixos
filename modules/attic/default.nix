# The attic binary cache in a microVM, on the `vms/attic` logical volume. The
# host forwards the cache's port to it, so the LAN reaches the cache at the
# host's address.
{
  config,
  pkgs,
  ...
}:
let
  net = import ./net.nix;
  inherit (config.clan.core.vars.generators) attic-token-key attic-signing uptime-push;
  inherit (config.vmHost) lanAddress;
  guest = config.microvm.vms.attic.config.config;
  atticdConfig = (pkgs.formats.toml { }).generate "atticd.toml" guest.services.atticd.settings;
  gatusIp = config.vmHost.gatus.ip;
  gatusPort = config.vmHost.gatus.port;
in
{
  imports = [ ../vm-host ];

  config = {
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
      files.token.secret = true;
      runtimeInputs = [ pkgs.attic-server ];
      script = ''
        set -a
        . "$in/attic-token-key/env"
        atticadm -f ${atticdConfig} make-token --sub builder --validity 10y \
          --pull ${net.cache} --push ${net.cache} | tr -d '\n' > "$out/token"
      '';
    };

    vmHost.vms.attic = {
      inherit (net) tap host prefixLength;
      secrets = {
        atticd-env = attic-token-key.files.env.path;
        attic-signing-key = attic-signing.files.key.path;
        uptime-push-token = uptime-push.files.token.path;
      };
      # The VM may only answer and push to Gatus: no host, pods or services.
      filter = [
        "-d ${gatusIp} -p tcp --dport ${gatusPort} -j RETURN"
        "-j DROP"
      ];
    };

    microvm.vms.attic.config = {
      imports = [ ./guest.nix ];
      attic = {
        secrets = config.vmHost.vms.attic.secretsImage;
        apiEndpoint = "http://${lanAddress}:${toString net.port}/";
        gatusUrl = config.diskPush.url;
        gatusPubkey = config.diskPush.pubkeyFile;
      };
    };

    networking.nat = {
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
        iptables -w -t nat -A nixos-nat-post -s ${net.guest} -d ${gatusIp} -p tcp --dport ${gatusPort} -o ${config.vmHost.interface} -j MASQUERADE
      '';
    };
  };
}
