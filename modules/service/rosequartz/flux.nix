# WIP

{
  config,
  lib,
  pkgs,
  fluxFor,
  ...
}:
let
  cfg = config.cluster.rosequartz;

  flux = fluxFor pkgs.system;

  # gotk-components.yaml + gotk-sync.yaml + kustomization.yaml — the full Flux
  # bootstrap bundle, laid out exactly like `flux bootstrap`, built at eval time
  # (no cluster access needed). the-cluster is public, so no deploy-key/secretRef
  # is needed. This directory can be copied verbatim into the-cluster's
  # clusters/rosequartz/flux-system once the cluster is self-managing.
  manifests = flux.gotkComponents {
    url = "https://github.com/UnstoppableMango/the-cluster";
    branch = "main";
    namespace = "flux-system";
    path = "./clusters/rosequartz";
    # a2b's callPackage injects pkgs.semver into the `semver` arg, which would
    # override the branch ref with a nix store path. Pin it to null so the
    # GitRepository tracks `branch: main`.
    semver = null;
  };

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
      cp -r ${manifests}/. manifests/
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
    cluster.rosequartz.pki.certs.admin-cert = {
      cn = "kubernetes-admin";
      org = "system:masters";
      profile = "client";
      owner = "kubernetes";
    };

    services.kubernetes.kubelet.seedDockerImages = [ image ];

    # Idempotently re-applies the gotk manifests every 5 minutes. Once Flux's
    # own controllers are up they reconcile from the-cluster on their own;
    # this pod just keeps drift-correcting (e.g. if flux-system is deleted)
    # for free, with no manual bootstrap step required after deploy.
    services.kubernetes.kubelet.manifests."flux-bootstrap" = {
      apiVersion = "v1";
      kind = "Pod";
      metadata = {
        name = "flux-bootstrap";
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
