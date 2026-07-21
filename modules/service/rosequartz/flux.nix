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

  # gotk-components.yaml — Flux controller manifests, built at eval time.
  componentsManifest = flux.install { namespace = "flux-system"; };

  # gotk-sync.yaml — GitRepository + Kustomization pointing Flux at itself.
  # the-cluster repo is public, so no deploy key is needed.
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

  # Laid out like `flux bootstrap` would, so it can later be copied verbatim
  # into the-cluster's flux-system dir. Passed to inoculant via `manifestFiles`.
  fluxManifests = pkgs.runCommand "rosequartz-flux-manifests" { } ''
    mkdir -p $out
    cp ${componentsManifest} $out/gotk-components.yaml
    cat ${sourceManifest} ${kustomizationManifest} > $out/gotk-sync.yaml
  '';

  # nixpkgs computes these regardless of addonManager.enable, which rosequartz
  # keeps false. Hand them to inoculant instead of running kube-addon-manager.
  addonManifests =
    config.services.kubernetes.addonManager.addons
    // config.services.kubernetes.addonManager.bootstrapAddons;
in
{
  imports = [ inputs.inoculant.nixosModules.default ];

  options.cluster.rosequartz.fluxBootstrap = {
    enable = lib.mkEnableOption "coredns + flux bootstrap via inoculant";
  };

  config = lib.mkIf cfg.fluxBootstrap.enable {
    cluster.rosequartz.pki.certs.inoculant-cert = {
      cn = "inoculant";
      org = "system:masters";
      profile = "client";
      owner = "kubernetes";
    };

    # inoculant normally mints this cert via nixpkgs' easyCerts flow, which we
    # don't run. Point it at our cfssl cert instead; mkForce the whole attrs
    # since `pki.certs` isn't a submodule and inoculant also writes this key.
    services.kubernetes.pki.certs = lib.mkForce {
      inoculant = {
        cert = cfg.pki.certs."inoculant-cert".cert;
        key = cfg.pki.certs."inoculant-cert".key;
      };
    };

    services.kubernetes.inoculant = {
      enable = true;
      manifests = addonManifests;
      manifestFiles = [ fluxManifests ];
    };
  };
}
