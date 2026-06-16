{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.cluster.rosequartz;
  pki = import ./pki.nix { inherit lib pkgs; };

  cert = name: config.clan.core.vars.generators."rosequartz-${name}".files;

  etcdClientEndpoints = map (n: "https://${n.ip}:2379") cfg.nodes;
  etcdPeerEndpoints = map (n: "${n.name}=https://${n.ip}:2380") cfg.nodes;

  localNode = lib.findFirst (
    n: n.ip == cfg.advertiseAddress
  ) (throw "no rosequartz node matches advertiseAddress ${cfg.advertiseAddress}") cfg.nodes;
in
{
  imports = [ ./network.nix ];

  options.cluster.rosequartz = {
    nodes = lib.mkOption {
      type = lib.types.listOf (
        lib.types.submodule {
          options = {
            name = lib.mkOption { type = lib.types.str; };
            ip = lib.mkOption { type = lib.types.str; };
          };
        }
      );
      description = "All control plane nodes with their names and IPs.";
    };

    vip = lib.mkOption {
      type = lib.types.str;
      description = "Keepalived virtual IP (VIP) for the cluster.";
    };

    apiserverPort = lib.mkOption {
      type = lib.types.port;
      default = 6444;
      description = "Port the local apiserver binds to (HAProxy fronts 6443 to this port).";
    };

    interface = lib.mkOption {
      type = lib.types.str;
      description = "Network interface for keepalived VRRP.";
    };

    virtualRouterId = lib.mkOption {
      type = lib.types.int;
      default = 50;
      description = "Keepalived VRRP virtual router ID (1-255, unique per subnet).";
    };

    serviceClusterIP = lib.mkOption {
      type = lib.types.str;
      default = "10.0.0.1";
      description = "First IP of the service CIDR; included in apiserver SANs.";
    };

    clusterName = lib.mkOption {
      type = lib.types.str;
      description = "Cluster name; used in TLS certificate subject names.";
    };

    advertiseAddress = lib.mkOption {
      type = lib.types.str;
      description = "IP address this node advertises for the apiserver and etcd.";
    };

    keepalivedPriority = lib.mkOption {
      type = lib.types.int;
      default = 100;
      description = "VRRP priority — highest wins the VIP.";
    };

    etcd.advertiseClientUrls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "etcd client URLs advertised to the cluster (https://<node-ip>:2379).";
    };

    etcd.initialAdvertisePeerUrls = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "etcd peer URLs advertised during bootstrap (https://<node-ip>:2380).";
    };

    etcd.initialCluster = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      description = "etcd initial cluster peer URLs; defaults to all nodes, override during member replacement.";
    };

    etcd.initialClusterState = lib.mkOption {
      type = lib.types.enum [
        "new"
        "existing"
      ];
      default = "new";
      description = "etcd initial cluster state; set to \"existing\" when replacing a member or restoring into a live cluster.";
    };
  };

  config = {
    cluster.rosequartz.etcd.initialCluster = lib.mkDefault etcdPeerEndpoints;

    clan.core.vars.generators =
      pki.caGenerator
      // pki.mkControlPlaneGenerators {
        inherit (cfg)
          nodes
          vip
          advertiseAddress
          serviceClusterIP
          ;
        inherit localNode;
      };

    # -------------------------------------------------------------------------
    # Kubernetes control plane
    # -------------------------------------------------------------------------
    services.kubernetes = {
      roles = [ "master" ];
      masterAddress = cfg.vip;
      apiserverAddress = "https://${cfg.vip}:6443";
      easyCerts = false;
      caFile = (cert "ca")."crt".path;

      apiserver = {
        advertiseAddress = cfg.advertiseAddress;
        securePort = cfg.apiserverPort;
        clientCaFile = (cert "ca")."crt".path;
        tlsCertFile = (cert "apiserver-cert")."crt".path;
        tlsKeyFile = (cert "apiserver-cert")."key".path;
        serviceAccountKeyFile = (cert "sa")."crt".path;
        serviceAccountSigningKeyFile = (cert "sa")."key".path;
        kubeletClientCertFile = (cert "apiserver-kubelet-client-cert")."crt".path;
        kubeletClientKeyFile = (cert "apiserver-kubelet-client-cert")."key".path;
        etcd = {
          servers = etcdClientEndpoints;
          caFile = (cert "ca")."crt".path;
          certFile = (cert "etcd-client-cert")."crt".path;
          keyFile = (cert "etcd-client-cert")."key".path;
        };
      };

      controllerManager = {
        serviceAccountKeyFile = (cert "sa")."key".path;
        kubeconfig = {
          certFile = (cert "controller-manager-cert")."crt".path;
          keyFile = (cert "controller-manager-cert")."key".path;
        };
      };

      scheduler.kubeconfig = {
        certFile = (cert "scheduler-cert")."crt".path;
        keyFile = (cert "scheduler-cert")."key".path;
      };

      kubelet = {
        clientCaFile = (cert "ca")."crt".path;
        tlsCertFile = (cert "kubelet-cert")."crt".path;
        tlsKeyFile = (cert "kubelet-cert")."key".path;
        kubeconfig = {
          certFile = (cert "kubelet-client-cert")."crt".path;
          keyFile = (cert "kubelet-client-cert")."key".path;
        };
      };
    };

    # -------------------------------------------------------------------------
    # etcd cluster
    # -------------------------------------------------------------------------
    services.etcd = {
      name = localNode.name;
      listenClientUrls = [ "https://0.0.0.0:2379" ];
      listenPeerUrls = [ "https://0.0.0.0:2380" ];
      advertiseClientUrls = cfg.etcd.advertiseClientUrls;
      initialAdvertisePeerUrls = cfg.etcd.initialAdvertisePeerUrls;
      initialCluster = cfg.etcd.initialCluster;
      initialClusterState = cfg.etcd.initialClusterState;
      clientCertAuth = true;
      peerClientCertAuth = true;
      trustedCaFile = (cert "ca")."crt".path;
      certFile = (cert "etcd-server-cert")."crt".path;
      keyFile = (cert "etcd-server-cert")."key".path;
      peerCertFile = (cert "etcd-peer-cert")."crt".path;
      peerKeyFile = (cert "etcd-peer-cert")."key".path;
      peerTrustedCaFile = (cert "ca")."crt".path;
    };

    # -------------------------------------------------------------------------
    # keepalived — floating VIP
    # -------------------------------------------------------------------------
    services.keepalived = {
      enable = true;
      openFirewall = true;
      vrrpInstances.VI_K8S = {
        interface = cfg.interface;
        state = "BACKUP";
        virtualRouterId = cfg.virtualRouterId;
        priority = cfg.keepalivedPriority;
        virtualIps = [ { addr = "${cfg.vip}/24"; } ];
      };
    };

    # -------------------------------------------------------------------------
    # HAProxy — LB from VIP:6443 → apiserver:6444 on all nodes
    # -------------------------------------------------------------------------
    services.haproxy = {
      enable = true;
      config = ''
        global
          log /dev/log local0
          maxconn 4000

        defaults
          log global
          mode tcp
          timeout connect 5s
          timeout client 30s
          timeout server 30s

        frontend k8s-api
          bind *:6443
          default_backend k8s-api-backend

        backend k8s-api-backend
          balance roundrobin
          option tcp-check
          ${lib.concatMapStringsSep "\n          " (
            n: "server ${n.name} ${n.ip}:${toString cfg.apiserverPort} check"
          ) cfg.nodes}
      '';
    };

    # -------------------------------------------------------------------------
    # Network
    # -------------------------------------------------------------------------
    networking.firewall = {
      allowedTCPPorts = [
        6443 # HAProxy / kube-apiserver (external via VIP)
        cfg.apiserverPort # kube-apiserver (internal)
        2379 # etcd client
        2380 # etcd peer
        10250 # kubelet API
        10257 # kube-controller-manager
        10259 # kube-scheduler
      ];
    };

    boot.kernelModules = [
      "br_netfilter"
      "wireguard"
    ];

    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-iptables" = lib.mkDefault 1;
      "net.bridge.bridge-nf-call-ip6tables" = lib.mkDefault 1;
      "net.ipv4.ip_forward" = lib.mkDefault 1;
    };
  };
}
