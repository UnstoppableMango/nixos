{
  config,
  lib,
  ...
}:
let
  cfg = config.cluster.rosequartz;
in
{
  options.cluster.rosequartz.coredns = {
    enable = lib.mkEnableOption "coredns bootstrap via inoculant";

    manifests = lib.mkOption {
      type = lib.types.attrsOf lib.types.attrs;
      # nixpkgs computes these regardless of addonManager.enable, which we keep false.
      # Excludes bootstrapAddons (RBAC for kube-addon-manager, which never runs here).
      default = config.services.kubernetes.addonManager.addons;
      description = "CoreDNS manifests applied via inoculant.";
    };
  };

  config = lib.mkIf cfg.coredns.enable {
    # Reuses the kubernetes-admin cert from kubeconfig.nix rather than minting a dedicated
    # one; inoculant's init container uses it to mint scoped RBAC + a token kubeconfig.
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
