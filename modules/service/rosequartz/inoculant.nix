{
  config,
  lib,
  inputs,
  ...
}:
let
  cfg = config.cluster.rosequartz;
in
{
  # Not importing inputs.inoculant.nixosModules.default here: flux.nix already imports it
  # unconditionally, and control-plane.nix imports both files. NixOS's module dedup keys
  # imports by call-site file, so importing the same module value from two files throws
  # "option already declared" instead of deduping — only one of the two may carry it.
  options.cluster.rosequartz.coredns = {
    enable = lib.mkEnableOption "coredns bootstrap via inoculant";

    manifests = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      # nixpkgs computes these attrs (coredns Deployment/Service/ConfigMap/RBAC) regardless
      # of addonManager.enable, which rosequartz keeps false. Deliberately excludes
      # addonManager.bootstrapAddons (RBAC for the system:kube-addon-manager principal,
      # which never runs here) — that's not coredns.
      default = config.services.kubernetes.addonManager.addons;
      description = "CoreDNS manifests applied via inoculant.";
    };
  };

  config = lib.mkIf cfg.coredns.enable {
    # services.kubernetes.inoculant.pkg defaults to a buildGoApplication derivation, which
    # only exists once the gomod2nix overlay is applied — inoculant's own flake does this
    # in its perSystem, but that doesn't reach a NixOS module consumed from another flake.
    nixpkgs.overlays = [ inputs.gomod2nix.overlays.default ];

    # inoculant's bootstrap init container mints scoped RBAC + a token kubeconfig using
    # this cert, then the main container applies manifests with the scoped token. Reuses
    # the existing kubernetes-admin (system:masters) cert from kubeconfig.nix rather than
    # minting a dedicated one.
    services.kubernetes.pki.certs.clusterAdmin = {
      cert = cfg.pki.certs."admin-cert".cert;
      key = cfg.pki.certs."admin-cert".key;
    };

    services.kubernetes.inoculant = {
      enable = true;
      manifests = cfg.coredns.manifests;
    };
  };
}
