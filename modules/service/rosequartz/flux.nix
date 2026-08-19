{
  config,
  lib,
  pkgs,
  inputs,
  ...
}:
let
  inherit (pkgs.stdenv.hostPlatform) system;

  cfg = config.cluster.rosequartz;

  flux = inputs.a2b.legacyPackages.${system}.lib.flux;

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

  # manifestFiles content isn't introspectable by Nix, so the bootstrap init
  # container's --allow GVK scoping (normally derived from `manifests`) has to
  # be supplied explicitly. Walk every YAML document in fluxManifests with
  # yq-go and collect the distinct apiVersion/kind pairs actually present.
  fluxManifestGVKsJson =
    pkgs.runCommand "rosequartz-flux-manifest-gvks.json"
      {
        nativeBuildInputs = [
          pkgs.yq-go
          pkgs.jq
        ];
      }
      ''
        yq eval-all -o=json '{"apiVersion": .apiVersion, "kind": .kind}' \
          ${fluxManifests}/gotk-components.yaml ${fluxManifests}/gotk-sync.yaml \
          | jq -s 'unique' > $out
      '';

  fluxManifestGVKs = map (
    { apiVersion, kind }:
    let
      parts = lib.splitString "/" apiVersion;
    in
    {
      group = if lib.length parts == 2 then lib.head parts else "";
      ver = lib.last parts;
      inherit kind;
    }
  ) (builtins.fromJSON (builtins.readFile fluxManifestGVKsJson));
in
{
  options.cluster.rosequartz.flux = {
    enable = lib.mkEnableOption "flux bootstrap via inoculant";
  };

  config = lib.mkIf cfg.flux.enable {
    services.kubernetes.inoculant = {
      enable = true;
      manifestFiles = [ fluxManifests ];
      additionalAllowedGVKs = fluxManifestGVKs;
    };
  };
}
