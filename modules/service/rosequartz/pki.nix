{ lib, pkgs, keyBits ? 2048, certValidityDays ? 3650 }:
let
  clientExt = ''
    keyUsage=critical,digitalSignature,keyEncipherment
    extendedKeyUsage=clientAuth'';

  serverExt = sans: ''
    keyUsage=critical,digitalSignature,keyEncipherment
    extendedKeyUsage=serverAuth
    subjectAltName=${sans}'';

  peerExt = sans: ''
    keyUsage=critical,digitalSignature,keyEncipherment
    extendedKeyUsage=serverAuth,clientAuth
    subjectAltName=${sans}'';

  sign = subj: ext: ''
    set -euo pipefail
    openssl req -newkey rsa:${toString keyBits} -nodes \
      -keyout "$out/key" -subj "${subj}" -out tmp.csr 2>/dev/null
    openssl x509 -req -in tmp.csr \
      -CA "$in/rosequartz-ca/crt" -CAkey "$in/rosequartz-ca/key" -CAcreateserial \
      -days ${toString certValidityDays} -sha256 \
      -extfile <(printf '%s' "${ext}") \
      -out "$out/crt" 2>/dev/null
  '';

  mkCert = share: subj: ext: owner: {
    inherit share;
    runtimeInputs = [ pkgs.openssl ];
    dependencies = [ "rosequartz-ca" ];
    files."crt".secret = false;
    files."key" = {
      secret = true;
      inherit owner;
    };
    script = sign subj ext;
  };

  mkSharedCert = mkCert true;
  mkNodeCert = mkCert false;
in
{
  inherit clientExt serverExt peerExt sign mkCert mkSharedCert mkNodeCert;

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
      nodeSANs = lib.concatMapStringsSep "," (ip: "IP:${ip}") nodeIps;
      apiserverSANs = lib.concatStringsSep "," [
        "IP:${vip}"
        nodeSANs
        "IP:${serviceClusterIP}"
        "IP:127.0.0.1"
        "DNS:kubernetes"
        "DNS:kubernetes.default"
        "DNS:kubernetes.default.svc"
        "DNS:kubernetes.default.svc.cluster.local"
        "DNS:localhost"
      ];
      localSANs = "IP:${advertiseAddress},IP:127.0.0.1";
    in
    {
      "rosequartz-sa" = {
        share = true;
        runtimeInputs = [ pkgs.openssl ];
        files."key" = {
          secret = true;
          owner = "kubernetes";
        };
        files."pub".secret = false;
        script = ''
          set -euo pipefail
          openssl genrsa -out "$out/key" ${toString keyBits} 2>/dev/null
          openssl rsa -in "$out/key" -pubout -out "$out/pub" 2>/dev/null
        '';
      };

      "rosequartz-apiserver-cert" =
        mkSharedCert "/CN=kube-apiserver" (serverExt apiserverSANs) "kubernetes";

      "rosequartz-apiserver-kubelet-client-cert" =
        mkSharedCert "/CN=kube-apiserver-kubelet-client/O=system:masters" clientExt "kubernetes";

      "rosequartz-controller-manager-cert" =
        mkSharedCert "/CN=system:kube-controller-manager/O=system:kube-controller-manager" clientExt "kubernetes";

      "rosequartz-scheduler-cert" =
        mkSharedCert "/CN=system:kube-scheduler/O=system:kube-scheduler" clientExt "kubernetes";

      "rosequartz-etcd-client-cert" =
        mkSharedCert "/CN=kube-apiserver-etcd-client/O=system:masters" clientExt "kubernetes";

      "rosequartz-admin-cert" =
        mkSharedCert "/CN=kubernetes-admin/O=system:masters" clientExt "kubernetes";

      "rosequartz-etcd-server-cert" = mkNodeCert "/CN=etcd-server" (peerExt localSANs) "etcd";

      "rosequartz-etcd-peer-cert" = mkNodeCert "/CN=etcd-peer" (peerExt localSANs) "etcd";

      "rosequartz-kubelet-cert" =
        mkNodeCert "/CN=system:node:${localNode.name}/O=system:nodes" (peerExt "IP:${advertiseAddress}") "root";

      "rosequartz-kubelet-client-cert" =
        mkNodeCert "/CN=system:node:${localNode.name}/O=system:nodes" clientExt "root";
    };

  mkWorkerGenerators =
    { advertiseAddress, hostName }:
    {
      "rosequartz-worker-kubelet-cert" =
        mkNodeCert "/CN=system:node:${hostName}/O=system:nodes" (peerExt "IP:${advertiseAddress}") "root";

      "rosequartz-worker-kubelet-client-cert" =
        mkNodeCert "/CN=system:node:${hostName}/O=system:nodes" clientExt "root";
    };

  flannelGenerator = {
    "rosequartz-flannel-cert" = mkSharedCert "/CN=flannel/O=system:masters" clientExt "root";
  };
}
