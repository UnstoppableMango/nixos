# The builder microVM. Of the LAN it reaches only attic and Gatus' push port.
{ config, lib, ... }:
let
  accounts = [
    "unmango"
    "unstoppablemango"
  ];
  net = import ./net.nix;
  attic = import ../attic/net.nix;
  inherit (config.vmHost) gatus;
  inherit (config.clan.core.vars.generators) attic-push-token attic-signing uptime-push;
  agentFiles = account: config.clan.core.vars.generators."hercules-ci-agent-${account}".files;
in
{
  imports = [
    ../vm-host
  ]
  ++ map (import ../service/hercules-ci-agent/vars.nix) accounts;

  config = {
    vmHost.vms.builder = {
      inherit (net) tap host prefixLength;
      secrets = {
        attic-push-token = attic-push-token.files.token.path;
        uptime-push-token = uptime-push.files.token.path;
      }
      // lib.mergeAttrsList (
        map (account: {
          "${account}-cluster-join-token" = (agentFiles account)."cluster-join-token.key".path;
          "${account}-binary-caches" = (agentFiles account)."binary-caches.json".path;
        }) accounts
      );
      filter = [
        "-d ${attic.guest} -p tcp --dport ${toString attic.port} -j RETURN"
        "-d ${gatus.ip} -p tcp --dport ${gatus.port} -j RETURN"
      ]
      # Nothing else on the LAN, the host or the cluster.
      ++ map (range: "-d ${range} -j DROP") [
        "0.0.0.0/8"
        "10.0.0.0/8"
        "100.64.0.0/10"
        "127.0.0.0/8"
        "169.254.0.0/16"
        "172.16.0.0/12"
        "192.168.0.0/16"
        "224.0.0.0/3"
      ];
    };

    networking.nat.internalIPs = [ "${net.guest}/32" ];

    microvm.vms.builder.config = {
      imports = [ ./guest.nix ];
      builder = {
        inherit accounts;
        secrets = config.vmHost.vms.builder.secretsImage;
        atticPubkey = attic-signing.files.pubkey.value;
        gatusUrl = config.diskPush.url;
        gatusPubkey = config.diskPush.pubkeyFile;
      };
    };

    systemd.services."microvm@builder".serviceConfig = {
      # The VM reports ready once booted, which waits on `nix-store --verify --repair`.
      TimeoutStartSec = 30 * 60;
      CPUWeight = 50;
      IOWeight = 50;
    };
  };
}
