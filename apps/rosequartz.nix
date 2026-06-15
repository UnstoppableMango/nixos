{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      certs =
        self.clanInternals.machines.aarch64-linux.pik8s4.config.clan.core.vars.generators."rosequartz-certs".files;
    in
    {
      apps.rosequartz-kubeconfig =
        let
          script = pkgs.writeShellApplication {
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

              printf '%s' ${pkgs.lib.escapeShellArg certs."ca-crt".value} > "$CA"
              printf '%s' ${pkgs.lib.escapeShellArg certs."admin-crt".value} > "$CRT"
              sops --decrypt --extract '["data"]' \
                "$FLAKE_DIR/vars/shared/rosequartz-certs/admin-key/secret" > "$KEY"

              KUBECONFIG="$OUTPUT" kubectl config set-cluster rosequartz \
                --server=https://192.168.1.100:6443 \
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
        in
        {
          type = "app";
          program = "${script}/bin/rosequartz-kubeconfig";
        };
    };
}
