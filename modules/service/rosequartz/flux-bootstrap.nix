{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  cfg = config.cluster.rosequartz;

  flux = inputs.a2b.legacyPackages.${pkgs.system}.lib.flux;

  # gotk-components.yaml — Flux controller manifests, built at eval time via
  # `flux install --export` (no cluster access needed to generate this).
  componentsManifest = flux.install { namespace = "flux-system"; };

  # gotk-sync.yaml — GitRepository + Kustomization pointing Flux at itself.
  # the-cluster is public, so no deploy-key/secretRef is needed here.
  sourceManifest = flux.createSourceGit {
    name = "flux-system";
    namespace = "flux-system";
    url = "https://github.com/UnstoppableMango/the-cluster";
    branch = "main";
  };

  kustomizationManifest = flux.createKustomization {
    name = "flux-system";
    namespace = "flux-system";
    source = "flux-system";
    path = "./clusters/rosequartz";
    prune = true;
  };

  # Bundled the way `flux bootstrap` lays them out, so this directory can be
  # copied verbatim into the-cluster's clusters/rosequartz/flux-system once
  # the cluster is self-managing.
  manifests = pkgs.runCommand "rosequartz-flux-manifests" { } ''
    mkdir -p $out
    cp ${componentsManifest} $out/gotk-components.yaml
    cat ${sourceManifest} ${kustomizationManifest} > $out/gotk-sync.yaml
    cat > $out/kustomization.yaml <<'EOF'
    apiVersion: kustomize.config.k8s.io/v1beta1
    kind: Kustomization
    resources:
      - gotk-components.yaml
      - gotk-sync.yaml
    EOF
  '';

  imageName = "rosequartz-flux-bootstrap";
  imageTag = "latest";

  # Image is built and preloaded locally (services.kubernetes.kubelet.seedDockerImages
  # below) — no registry, no internet access needed on the node at runtime.
  image = pkgs.dockerTools.buildLayeredImage {
    name = imageName;
    tag = imageTag;
    contents = [
      pkgs.kubectl
      pkgs.busybox
    ];
    extraCommands = ''
      mkdir -p manifests
      cp ${componentsManifest} manifests/gotk-components.yaml
      cat ${sourceManifest} ${kustomizationManifest} > manifests/gotk-sync.yaml
      cat > manifests/kustomization.yaml <<'EOF'
      apiVersion: kustomize.config.k8s.io/v1beta1
      kind: Kustomization
      resources:
        - gotk-components.yaml
        - gotk-sync.yaml
      EOF
    '';
    config.Entrypoint = [
      "/bin/sh"
      "-c"
      ''
        while true; do
          kubectl \
            --server=https://${cfg.vip}:6443 \
            --certificate-authority=/pki/ca.crt \
            --client-certificate=/pki/admin.crt \
            --client-key=/pki/admin.key \
            apply -k /manifests
          sleep 300
        done
      ''
    ];
  };
in
{
  options.cluster.rosequartz.fluxBootstrap = {
    enable = lib.mkEnableOption "flux bootstrap static pod";

    manifests = lib.mkOption {
      type = lib.types.package;
      readOnly = true;
      internal = true;
      description = "Generated gotk manifest bundle, for inspection or copying into the-cluster repo.";
      default = manifests;
    };
  };

  config = lib.mkIf config.cluster.rosequartz.fluxBootstrap.enable {
    clan.core.vars.generators = {
      "rosequartz-admin-cert" = lib.mkDefault (
        pki.mkSharedCert "/CN=kubernetes-admin/O=system:masters" pki.clientExt "kubernetes"
      );
    };

    services.kubernetes.kubelet.seedDockerImages = [ image ];

    # Idempotently re-applies the gotk manifests every 5 minutes. Once Flux's
    # own controllers are up they reconcile from the-cluster on their own;
    # this pod just keeps drift-correcting (e.g. if flux-system is deleted)
    # for free, with no manual bootstrap step required after deploy.
    services.kubernetes.kubelet.manifests."rosequartz-flux-bootstrap" = {
      apiVersion = "v1";
      kind = "Pod";
      metadata = {
        name = "rosequartz-flux-bootstrap";
        namespace = "kube-system";
      };
      spec = {
        restartPolicy = "Always";
        containers = [
          {
            name = "apply";
            image = "${imageName}:${imageTag}";
            imagePullPolicy = "Never";
            volumeMounts = [
              {
                name = "ca-crt";
                mountPath = "/pki/ca.crt";
                readOnly = true;
              }
              {
                name = "admin-crt";
                mountPath = "/pki/admin.crt";
                readOnly = true;
              }
              {
                name = "admin-key";
                mountPath = "/pki/admin.key";
                readOnly = true;
              }
            ];
          }
        ];
        volumes = [
          {
            name = "ca-crt";
            hostPath = {
              path = cfg.pki.ca.cert;
              type = "File";
            };
          }
          {
            name = "admin-crt";
            hostPath = {
              path = cfg.pki.certs."admin-cert".cert;
              type = "File";
            };
          }
          {
            name = "admin-key";
            hostPath = {
              path = cfg.pki.certs."admin-cert".key;
              type = "File";
            };
          }
        ];
      };
    };
  };
}
