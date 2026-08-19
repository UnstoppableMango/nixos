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
    # nixpkgs' cni-plugin-flannel FOD has a stale hash for the GitHub tarball.
    # Pin the actually-observed hash until nixpkgs fixes it.
    nixpkgs.overlays = [
      (_final: prev: {
        cni-plugin-flannel = prev.cni-plugin-flannel.overrideAttrs (old: {
          src = old.src.overrideAttrs (_: {
            outputHash = "sha256-lYn9qDmUn8g3nnD4wQqyzKjd/lPXqoER5nZuY0sVK0s=";
          });
        });
      })
    ];

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
      # Kubelet registers nodes with the short name; match that here too.
      nodeName = config.networking.hostName;
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
