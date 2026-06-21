{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.cluster.rosequartz;
  rosLib = import ./lib.nix;

  flannelKubeconfig = pkgs.writeText "flannel.kubeconfig" (
    rosLib.mkKubeconfig {
      ca = cfg.pki.ca.cert;
      server = "https://${cfg.vip}:6443";
      clusterName = cfg.clusterName;
      userName = "flannel";
      contextName = "flannel@${cfg.clusterName}";
      certFile = cfg.pki.certs."flannel-cert".cert;
      keyFile = cfg.pki.certs."flannel-cert".key;
    }
  );
in
{
  config = {
    cluster.rosequartz.pki.certs."flannel-cert" = {
      cn = "flannel";
      org = "system:masters";
      profile = "client";
      owner = "root";
    };

    services.kubernetes.flannel.enable = lib.mkForce false;
    services.flannel = {
      enable = true;
      storageBackend = "kubernetes";
      network = config.services.kubernetes.clusterCidr;
      kubeconfig = flannelKubeconfig;
    };
    services.kubernetes.kubelet.cni.config = lib.mkDefault [
      {
        name = "cni0";
        type = "flannel";
        cniVersion = "0.3.1";
        delegate = {
          isDefaultGateway = true;
          hairpinMode = true;
          bridge = "cni0";
        };
      }
    ];
    networking.dhcpcd.denyInterfaces = [
      "cni0*"
      "flannel*"
    ];

    networking.firewall.allowedUDPPorts = [
      8285 # flannel udp
      8472 # flannel VXLAN
    ];
  };
}
