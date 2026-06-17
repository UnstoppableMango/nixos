{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.cluster.rosequartz;

  flannelKubeconfig = pkgs.writeText "flannel.kubeconfig" ''
    apiVersion: v1
    kind: Config
    clusters:
    - cluster:
        certificate-authority: ${cfg.pki.ca.cert}
        server: https://${cfg.vip}:6443
      name: ${cfg.clusterName}
    contexts:
    - context:
        cluster: ${cfg.clusterName}
        user: flannel
      name: flannel@${cfg.clusterName}
    current-context: flannel@${cfg.clusterName}
    users:
    - name: flannel
      user:
        client-certificate: ${cfg.pki.certs."flannel-cert".cert}
        client-key: ${cfg.pki.certs."flannel-cert".key}
  '';
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
