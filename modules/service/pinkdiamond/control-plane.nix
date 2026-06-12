{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.cluster.pinkdiamond;
  certs = config.clan.core.vars.generators."pinkdiamond-certs".files;

  etcdClientEndpoints = map (n: "https://${n.ip}:2379") cfg.nodes;
  etcdPeerEndpoints = map (n: "${n.name}=https://${n.ip}:2380") cfg.nodes;

  nodeIps = map (n: n.ip) cfg.nodes;

  nodeSANs = lib.concatMapStringsSep "," (ip: "IP:${ip}") nodeIps;
  apiserverSANs = lib.concatStringsSep "," [
    "IP:${cfg.vip}"
    nodeSANs
    "IP:${cfg.serviceClusterIP}"
    "IP:127.0.0.1"
    "DNS:kubernetes"
    "DNS:kubernetes.default"
    "DNS:kubernetes.default.svc"
    "DNS:kubernetes.default.svc.cluster.local"
    "DNS:localhost"
  ];
in
{
  options.cluster.pinkdiamond = {
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

    pki.keyBits = lib.mkOption {
      type = lib.types.int;
      default = 2048;
      description = "RSA key size in bits for all generated certificates.";
    };

    pki.certValidityDays = lib.mkOption {
      type = lib.types.int;
      default = 3650;
      description = "Validity period in days for all generated certificates.";
    };
  };

  config = {
    cluster.pinkdiamond.etcd.initialCluster = lib.mkDefault etcdPeerEndpoints;

    clan.core.vars.generators."pinkdiamond-certs" = {
      share = true;

      runtimeInputs = [ pkgs.openssl ];

      prompts = {
        "ca-crt" = {
          description = "Cluster CA certificate (PEM)";
          type = "multiline";
        };
        "ca-key" = {
          description = "Cluster CA private key (PEM)";
          type = "multiline";
        };
      };

      files = {
        "ca-crt".secret = false;
        "apiserver-crt".secret = false;
        "apiserver-key".secret = true;
        "apiserver-kubelet-client-crt".secret = false;
        "apiserver-kubelet-client-key".secret = true;
        "controller-manager-crt".secret = false;
        "controller-manager-key".secret = true;
        "scheduler-crt".secret = false;
        "scheduler-key".secret = true;
        "kubelet-crt".secret = false;
        "kubelet-key".secret = true;
        "kubelet-client-crt".secret = false;
        "kubelet-client-key".secret = true;
        "etcd-ca-crt".secret = false;
        "etcd-server-crt".secret = false;
        "etcd-server-key".secret = true;
        "etcd-peer-crt".secret = false;
        "etcd-peer-key".secret = true;
        "etcd-client-crt".secret = false;
        "etcd-client-key".secret = true;
        "sa-pub".secret = false;
        "sa-key".secret = true;
      };

      script =
        let
          # sign <name> <subject> <ext>
          # Generates key + CSR, signs with prompts/ca-crt + ca-key, writes to $out/
          signFn = ''
            sign() {
              local name="$1" subj="$2" ext="$3"
              openssl req -newkey rsa:${toString cfg.pki.keyBits} -nodes \
                -keyout "$out/$name-key" -subj "$subj" -out "$name.csr" 2>/dev/null
              openssl x509 -req -in "$name.csr" \
                -CA "$prompts/ca-crt" -CAkey "$prompts/ca-key" -CAcreateserial \
                -days ${toString cfg.pki.certValidityDays} -sha256 \
                -extfile <(printf '%s' "$ext") \
                -out "$out/$name-crt" 2>/dev/null
            }
          '';
          serverExt =
            sans:
            "keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth\nsubjectAltName=${sans}";
          clientExt = "keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=clientAuth";
          peerExt =
            sans:
            "keyUsage=critical,digitalSignature,keyEncipherment\nextendedKeyUsage=serverAuth,clientAuth\nsubjectAltName=${sans}";
        in
        ''
          set -euo pipefail
          ${signFn}

          cp "$prompts/ca-crt" "$out/ca-crt"
          cp "$prompts/ca-crt" "$out/etcd-ca-crt"

          sign apiserver \
            "/CN=kube-apiserver" \
            "${serverExt apiserverSANs}"

          sign apiserver-kubelet-client \
            "/CN=kube-apiserver-kubelet-client/O=system:masters" \
            "${clientExt}"

          sign controller-manager \
            "/CN=system:kube-controller-manager/O=system:kube-controller-manager" \
            "${clientExt}"

          sign scheduler \
            "/CN=system:kube-scheduler/O=system:kube-scheduler" \
            "${clientExt}"

          sign kubelet \
            "/CN=system:node/O=system:nodes" \
            "${peerExt nodeSANs}"

          sign kubelet-client \
            "/CN=system:node:${cfg.clusterName}/O=system:nodes" \
            "${clientExt}"

          sign etcd-server \
            "/CN=etcd-server" \
            "${peerExt nodeSANs}"

          sign etcd-peer \
            "/CN=etcd-peer" \
            "${peerExt nodeSANs}"

          sign etcd-client \
            "/CN=kube-apiserver-etcd-client/O=system:masters" \
            "${clientExt}"

          # Service account key pair — shared generator ensures identical keys on all nodes
          openssl genrsa -out "$out/sa-key" ${toString cfg.pki.keyBits} 2>/dev/null
          openssl rsa -in "$out/sa-key" -pubout -out "$out/sa-pub" 2>/dev/null
        '';
    };

    # -------------------------------------------------------------------------
    # Kubernetes control plane
    # -------------------------------------------------------------------------
    services.kubernetes = {
      roles = [ "master" ];
      masterAddress = cfg.vip;
      apiserverAddress = "https://${cfg.vip}:6443";
      easyCerts = false;
      caFile = certs."ca-crt".path;

      apiserver = {
        advertiseAddress = cfg.advertiseAddress;
        securePort = cfg.apiserverPort;
        clientCaFile = certs."ca-crt".path;
        tlsCertFile = certs."apiserver-crt".path;
        tlsKeyFile = certs."apiserver-key".path;
        serviceAccountKeyFile = certs."sa-pub".path;
        serviceAccountSigningKeyFile = certs."sa-key".path;
        kubeletClientCertFile = certs."apiserver-kubelet-client-crt".path;
        kubeletClientKeyFile = certs."apiserver-kubelet-client-key".path;
        etcd = {
          servers = etcdClientEndpoints;
          caFile = certs."etcd-ca-crt".path;
          certFile = certs."etcd-client-crt".path;
          keyFile = certs."etcd-client-key".path;
        };
      };

      controllerManager = {
        serviceAccountKeyFile = certs."sa-key".path;
        kubeconfig = {
          certFile = certs."controller-manager-crt".path;
          keyFile = certs."controller-manager-key".path;
        };
      };

      scheduler.kubeconfig = {
        certFile = certs."scheduler-crt".path;
        keyFile = certs."scheduler-key".path;
      };

      kubelet = {
        clientCaFile = certs."ca-crt".path;
        tlsCertFile = certs."kubelet-crt".path;
        tlsKeyFile = certs."kubelet-key".path;
        kubeconfig = {
          certFile = certs."kubelet-client-crt".path;
          keyFile = certs."kubelet-client-key".path;
        };
      };
    };

    # -------------------------------------------------------------------------
    # etcd cluster
    # -------------------------------------------------------------------------
    services.etcd = {
      listenClientUrls = [ "https://0.0.0.0:2379" ];
      listenPeerUrls = [ "https://0.0.0.0:2380" ];
      advertiseClientUrls = cfg.etcd.advertiseClientUrls;
      initialAdvertisePeerUrls = cfg.etcd.initialAdvertisePeerUrls;
      initialCluster = cfg.etcd.initialCluster;
      initialClusterState = cfg.etcd.initialClusterState;
      clientCertAuth = true;
      peerClientCertAuth = true;
      trustedCaFile = certs."etcd-ca-crt".path;
      certFile = certs."etcd-server-crt".path;
      keyFile = certs."etcd-server-key".path;
      peerCertFile = certs."etcd-peer-crt".path;
      peerKeyFile = certs."etcd-peer-key".path;
      peerTrustedCaFile = certs."etcd-ca-crt".path;
    };

    # Flannel needs all etcd endpoints, not just the VIP
    services.flannel.etcd.endpoints = etcdClientEndpoints;

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
      allowedUDPPorts = [
        8285 # flannel udp
        8472 # flannel VXLAN
      ];
    };

    boot.kernelModules = [
      "br_netfilter"
      "wireguard"
    ];

    boot.kernel.sysctl = {
      "net.bridge.bridge-nf-call-iptables" = 1;
      "net.bridge.bridge-nf-call-ip6tables" = 1;
      "net.ipv4.ip_forward" = 1;
    };
  };
}
