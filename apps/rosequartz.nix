{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      vip = self.clanInternals.machines.aarch64-linux.pik8s4.config.cluster.rosequartz.vip;

      kubeconfigScript = pkgs.writeShellApplication {
        name = "rosequartz-kubeconfig";
        runtimeInputs = [
          pkgs.kubectl
          pkgs.sops
        ];
        text = ''
          FLAKE_DIR=''${FLAKE_DIR:-.}
          OUTPUT=''${ROSEQUARTZ_KUBECONFIG:-rosequartz.kubeconfig}

          CA=$(mktemp)
          CRT=$(mktemp)
          KEY=$(mktemp)
          trap 'rm -f $CA $CRT $KEY' EXIT

          cat "$FLAKE_DIR/vars/shared/rosequartz-ca/crt/value" > "$CA"
          cat "$FLAKE_DIR/vars/shared/rosequartz-admin-cert/crt/value" > "$CRT"
          sops --decrypt --extract '["data"]' \
            "$FLAKE_DIR/vars/shared/rosequartz-admin-cert/key/secret" > "$KEY"

          KUBECONFIG="$OUTPUT" kubectl config set-cluster rosequartz \
            --server=https://${vip}:6443 \
            --certificate-authority="$CA" \
            --embed-certs=true

          KUBECONFIG="$OUTPUT" kubectl config set-credentials admin \
            --client-certificate="$CRT" \
            --client-key="$KEY" \
            --embed-certs=true

          KUBECONFIG="$OUTPUT" kubectl config set-context rosequartz \
            --cluster=rosequartz --user=admin

          KUBECONFIG="$OUTPUT" kubectl config use-context rosequartz
          echo "Wrote $OUTPUT"
        '';
      };

      fluxBootstrapScript = pkgs.writeShellApplication {
        name = "rosequartz-flux-bootstrap";
        runtimeInputs = [
          pkgs.fluxcd
          kubeconfigScript
        ];
        text = ''
          FLAKE_DIR=''${FLAKE_DIR:-.}
          KUBECONFIG_FILE=$(mktemp --suffix=.kubeconfig)
          trap 'rm -f $KUBECONFIG_FILE' EXIT

          FLAKE_DIR="$FLAKE_DIR" ROSEQUARTZ_KUBECONFIG="$KUBECONFIG_FILE" \
            rosequartz-kubeconfig

          flux bootstrap github \
            --kubeconfig="$KUBECONFIG_FILE" \
            --owner=UnstoppableMango \
            --repository=the-cluster \
            --path=clusters/rosequartz \
            --personal
        '';
      };
    in
    {
      apps.rosequartz-kubeconfig = {
        type = "app";
        program = "${kubeconfigScript}/bin/rosequartz-kubeconfig";
      };

      apps.rosequartz-flux-bootstrap = {
        type = "app";
        program = "${fluxBootstrapScript}/bin/rosequartz-flux-bootstrap";
      };
    };
}
