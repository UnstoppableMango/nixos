{
  _class = "clan.service";
  manifest.name = "pinkdiamond";
  manifest.readme = builtins.readFile ./README.md;

  roles.control-plane = {
    description = "Control plane node";

    interface =
      { lib, ... }:
      {
        options.nodes = lib.mkOption {
          type = lib.types.listOf (
            lib.types.submodule {
              options = {
                name = lib.mkOption { type = lib.types.str; };
                ip = lib.mkOption { type = lib.types.str; };
              };
            }
          );
          description = "All control plane nodes with their names and IPs.";
        };

        options.vip = lib.mkOption {
          type = lib.types.str;
          description = "Keepalived virtual IP (VIP) for the cluster.";
        };

        options.clusterName = lib.mkOption {
          type = lib.types.str;
          description = "Cluster name; used in TLS certificate subject names.";
        };
      };

    perInstance =
      { settings, ... }:
      {
        nixosModule = {
          imports = [ ./control-plane.nix ];
          cluster.pinkdiamond = {
            inherit (settings) nodes vip clusterName;
          };
        };
      };
  };
}
