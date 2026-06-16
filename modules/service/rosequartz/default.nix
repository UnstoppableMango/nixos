let
  controlPlaneNodes =
    lib: roles:
    lib.mapAttrsToList (name: m: {
      inherit name;
      ip = m.settings.ip;
    }) roles.control-plane.machines;
in
{
  _class = "clan.service";
  manifest.name = "rosequartz";
  manifest.readme = builtins.readFile ./README.md;

  roles.control-plane = {
    description = "Control plane node";

    interface =
      { lib, ... }:
      {
        options.ip = lib.mkOption {
          type = lib.types.str;
          description = "IP address of this control plane node.";
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
      {
        lib,
        settings,
        roles,
        ...
      }:
      {
        nixosModule = {
          imports = [ ./control-plane.nix ];
          cluster.rosequartz = {
            nodes = controlPlaneNodes lib roles;
            inherit (settings) vip clusterName;
          };
        };
      };
  };

  roles.worker = {
    description = "Worker node";

    interface =
      { lib, ... }:
      {
        options.ip = lib.mkOption {
          type = lib.types.str;
          description = "IP address of this worker node.";
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
          imports = [ ./worker.nix ];
          cluster.rosequartz = {
            advertiseAddress = settings.ip;
            inherit (settings) vip clusterName;
          };
        };
      };
  };
}
