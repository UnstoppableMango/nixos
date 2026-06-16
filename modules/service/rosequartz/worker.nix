{
  config,
  lib,
  ...
}:
let
  cfg = config.cluster.rosequartz;
  inherit (cfg.pki.lib) clientExt peerExt mkNodeCert;

  cert = name: config.clan.core.vars.generators."rosequartz-${name}".files;
in
{
  imports = [ ./pki.nix ];

  options.cluster.rosequartz = {
    vip = lib.mkOption {
      type = lib.types.str;
      description = "Keepalived virtual IP (VIP) for the cluster.";
    };

    clusterName = lib.mkOption {
      type = lib.types.str;
      description = "Cluster name; used in TLS certificate subject names.";
    };

    advertiseAddress = lib.mkOption {
      type = lib.types.str;
      description = "IP address this worker node advertises (included in kubelet server cert SAN).";
    };
  };

  config = {
    clan.core.vars.generators = {
      "rosequartz-worker-kubelet-cert" = mkNodeCert
        "/CN=system:node:${config.networking.hostName}/O=system:nodes"
        (peerExt "IP:${cfg.advertiseAddress}")
        "root";

      "rosequartz-worker-kubelet-client-cert" = mkNodeCert
        "/CN=system:node:${config.networking.hostName}/O=system:nodes"
        clientExt
        "root";
    };

    # -------------------------------------------------------------------------
    # Kubernetes worker
    # -------------------------------------------------------------------------
    services.kubernetes = {
      roles = [ "node" ];
      masterAddress = cfg.vip;
      apiserverAddress = "https://${cfg.vip}:6443";
      easyCerts = false;
      caFile = (cert "ca")."crt".path;

      kubelet = {
        clientCaFile = (cert "ca")."crt".path;
        tlsCertFile = (cert "worker-kubelet-cert")."crt".path;
        tlsKeyFile = (cert "worker-kubelet-cert")."key".path;
        kubeconfig = {
          certFile = (cert "worker-kubelet-client-cert")."crt".path;
          keyFile = (cert "worker-kubelet-client-cert")."key".path;
        };
      };
    };

    # -------------------------------------------------------------------------
    # Network
    # -------------------------------------------------------------------------
    networking.firewall = {
      allowedTCPPorts = [
        10250 # kubelet API
      ];
      allowedUDPPorts = [
        8285 # flannel udp
        8472 # flannel VXLAN
      ];
    };

    boot.kernelModules = [
      "br_netfilter"
    ];

    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-iptables" = lib.mkDefault 1;
      "net.bridge.bridge-nf-call-ip6tables" = lib.mkDefault 1;
      "net.ipv4.ip_forward" = lib.mkDefault 1;
    };
  };
}
