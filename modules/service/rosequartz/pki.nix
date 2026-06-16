{
  lib,
  pkgs,
  certValidityDays ? 3650,
}:
let
  # ─── Config (JSON) ───────────────────────────────────────────────────────────

  expiryHours = certValidityDays * 24;

  signingConfigFile = pkgs.writeText "cfssl-signing-config.json" (
    builtins.toJSON {
      signing = {
        default.expiry = "${toString expiryHours}h";
        profiles = {
          server = {
            expiry = "${toString expiryHours}h";
            usages = [
              "digital signature"
              "server auth"
            ];
          };
          client = {
            expiry = "${toString expiryHours}h";
            usages = [
              "digital signature"
              "client auth"
            ];
          };
          peer = {
            expiry = "${toString expiryHours}h";
            usages = [
              "digital signature"
              "server auth"
              "client auth"
            ];
          };
        };
      };
    }
  );

  mkCsrFile =
    name:
    {
      cn,
      org ? null,
      hosts ? [ ],
    }:
    pkgs.writeText "${name}-csr.json" (
      builtins.toJSON {
        CN = cn;
        key = {
          algo = "ecdsa";
          size = 256;
        };
        hosts = hosts;
        names = lib.optional (org != null) { O = org; };
      }
    );

  # ─── Scripting ───────────────────────────────────────────────────────────────

  gencert = profile: csrFile: ''
    set -euo pipefail
    cfssl gencert \
      -ca "$in/rosequartz-ca/crt" \
      -ca-key "$in/rosequartz-ca/key" \
      -config ${signingConfigFile} \
      -profile ${profile} \
      ${csrFile} | cfssljson -bare cert
    mv cert.pem "$out/crt"
    mv cert-key.pem "$out/key"
    rm -f cert.csr
  '';

  mkCert = share: csrFile: profile: owner: {
    inherit share;
    runtimeInputs = [ pkgs.cfssl ];
    dependencies = [ "rosequartz-ca" ];
    files."crt".secret = false;
    files."key" = {
      secret = true;
      inherit owner;
    };
    script = gencert profile csrFile;
  };

  mkSharedCert = mkCert true;
  mkNodeCert = mkCert false;
in
{
  inherit
    mkCert
    mkSharedCert
    mkNodeCert
    mkCsrFile
    ;

  caGenerator = {
    "rosequartz-ca" = {
      share = true;
      prompts."ca-crt" = {
        description = "Cluster CA certificate (PEM)";
        type = "multiline";
      };
      prompts."ca-key" = {
        description = "Cluster CA private key (PEM)";
        type = "multiline-hidden";
      };
      files."crt".secret = false;
      files."key" = {
        secret = true;
        deploy = false;
      };
      script = ''
        set -euo pipefail
        cp "$prompts/ca-crt" "$out/crt"
        cp "$prompts/ca-key" "$out/key"
      '';
    };
  };

  mkControlPlaneGenerators =
    {
      nodes,
      vip,
      advertiseAddress,
      serviceClusterIP,
      localNode,
    }:
    let
      nodeIps = map (n: n.ip) nodes;
      apiserverHosts = [
        vip
      ]
      ++ nodeIps
      ++ [
        serviceClusterIP
        "127.0.0.1"
        "kubernetes"
        "kubernetes.default"
        "kubernetes.default.svc"
        "kubernetes.default.svc.cluster.local"
        "localhost"
      ];
      localHosts = [
        advertiseAddress
        "127.0.0.1"
      ];

      # --- CSR config ---
      saCsr = mkCsrFile "rosequartz-sa" { cn = "service-accounts"; };
      apiserverCsr = mkCsrFile "rosequartz-apiserver-cert" {
        cn = "kube-apiserver";
        hosts = apiserverHosts;
      };
      apiserverKubeletClientCsr = mkCsrFile "rosequartz-apiserver-kubelet-client-cert" {
        cn = "kube-apiserver-kubelet-client";
        org = "system:masters";
      };
      controllerManagerCsr = mkCsrFile "rosequartz-controller-manager-cert" {
        cn = "system:kube-controller-manager";
        org = "system:kube-controller-manager";
      };
      schedulerCsr = mkCsrFile "rosequartz-scheduler-cert" {
        cn = "system:kube-scheduler";
        org = "system:kube-scheduler";
      };
      etcdClientCsr = mkCsrFile "rosequartz-etcd-client-cert" {
        cn = "kube-apiserver-etcd-client";
        org = "system:masters";
      };
      adminCsr = mkCsrFile "rosequartz-admin-cert" {
        cn = "kubernetes-admin";
        org = "system:masters";
      };
      etcdServerCsr = mkCsrFile "rosequartz-etcd-server-cert" {
        cn = "etcd-server";
        hosts = localHosts;
      };
      etcdPeerCsr = mkCsrFile "rosequartz-etcd-peer-cert" {
        cn = "etcd-peer";
        hosts = localHosts;
      };
      kubeletCsr = mkCsrFile "rosequartz-kubelet-cert" {
        cn = "system:node:${localNode.name}";
        org = "system:nodes";
        hosts = [ advertiseAddress ];
      };
      kubeletClientCsr = mkCsrFile "rosequartz-kubelet-client-cert" {
        cn = "system:node:${localNode.name}";
        org = "system:nodes";
      };
    in
    {
      "rosequartz-sa" = mkSharedCert saCsr "client" "kubernetes";
      "rosequartz-apiserver-cert" = mkSharedCert apiserverCsr "server" "kubernetes";
      "rosequartz-apiserver-kubelet-client-cert" =
        mkSharedCert apiserverKubeletClientCsr "client"
          "kubernetes";
      "rosequartz-controller-manager-cert" = mkSharedCert controllerManagerCsr "client" "kubernetes";
      "rosequartz-scheduler-cert" = mkSharedCert schedulerCsr "client" "kubernetes";
      "rosequartz-etcd-client-cert" = mkSharedCert etcdClientCsr "client" "kubernetes";
      "rosequartz-admin-cert" = mkSharedCert adminCsr "client" "kubernetes";
      "rosequartz-etcd-server-cert" = mkNodeCert etcdServerCsr "peer" "etcd";
      "rosequartz-etcd-peer-cert" = mkNodeCert etcdPeerCsr "peer" "etcd";
      "rosequartz-kubelet-cert" = mkNodeCert kubeletCsr "peer" "root";
      "rosequartz-kubelet-client-cert" = mkNodeCert kubeletClientCsr "client" "root";
    };

  mkWorkerGenerators =
    { advertiseAddress, hostName }:
    let
      workerKubeletCsr = mkCsrFile "rosequartz-worker-kubelet-cert" {
        cn = "system:node:${hostName}";
        org = "system:nodes";
        hosts = [ advertiseAddress ];
      };
      workerKubeletClientCsr = mkCsrFile "rosequartz-worker-kubelet-client-cert" {
        cn = "system:node:${hostName}";
        org = "system:nodes";
      };
    in
    {
      "rosequartz-worker-kubelet-cert" = mkNodeCert workerKubeletCsr "peer" "root";
      "rosequartz-worker-kubelet-client-cert" = mkNodeCert workerKubeletClientCsr "client" "root";
    };

  flannelGenerator =
    let
      flannelCsr = mkCsrFile "rosequartz-flannel-cert" {
        cn = "flannel";
        org = "system:masters";
      };
    in
    {
      "rosequartz-flannel-cert" = mkSharedCert flannelCsr "client" "root";
    };
}
