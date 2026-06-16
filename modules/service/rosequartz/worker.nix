{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.cluster.rosequartz;
  certs = config.clan.core.vars.generators."rosequartz-worker-certs".files;

  etcdClientEndpoints = map (n: "https://${n.ip}:2379") cfg.nodes;

  workerSAN = "IP:${cfg.advertiseAddress}";
in
{
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
      description = "Control plane nodes; used to derive etcd endpoints for flannel.";
    };

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
    clan.core.vars.generators."rosequartz-worker-certs" = {
      share = false;

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
        "kubelet-crt".secret = false;
        "kubelet-key".secret = true;
        "kubelet-client-crt".secret = false;
        "kubelet-client-key".secret = true;
        "etcd-client-crt".secret = false;
        "etcd-client-key".secret = true;
      };

      script =
        let
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

          clientExt = ''
            keyUsage=critical,digitalSignature,keyEncipherment
            extendedKeyUsage=clientAuth'';

          peerExt = sans: ''
            keyUsage=critical,digitalSignature,keyEncipherment
            extendedKeyUsage=serverAuth,clientAuth
            subjectAltName=${sans}'';
        in
        ''
          set -euo pipefail
          ${signFn}

          cp "$prompts/ca-crt" "$out/ca-crt"

          sign kubelet \
            "/CN=system:node:${cfg.clusterName}/O=system:nodes" \
            "${peerExt workerSAN}"

          sign kubelet-client \
            "/CN=system:node:${cfg.clusterName}/O=system:nodes" \
            "${clientExt}"

          sign etcd-client \
            "/CN=kube-apiserver-etcd-client/O=system:masters" \
            "${clientExt}"
        '';
    };

    # -------------------------------------------------------------------------
    # Kubernetes worker
    # -------------------------------------------------------------------------
    services.kubernetes = {
      roles = [ "node" ];
      masterAddress = cfg.vip;
      apiserverAddress = "https://${cfg.vip}:6443";
      easyCerts = false;
      caFile = certs."ca-crt".path;

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

    services.kubernetes.flannel.enable = lib.mkForce false;
    services.flannel = {
      enable = true;
      storageBackend = "etcd";
      network = config.services.kubernetes.clusterCidr;
      etcd = {
        endpoints = etcdClientEndpoints;
        caFile = certs."ca-crt".path;
        certFile = certs."etcd-client-crt".path;
        keyFile = certs."etcd-client-key".path;
      };
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
