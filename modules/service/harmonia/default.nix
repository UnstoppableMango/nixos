{ lib, ... }:
{
  _class = "clan.service";
  manifest.name = "harmonia";
  manifest.description = "Serve a machine's own nix store to the clan as a signed binary cache";
  manifest.categories = [ "System" ];
  manifest.readme = builtins.readFile ./README.md;

  roles.server = {
    description = "A machine whose nix store is served to the clan";

    interface.options = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 5000;
        description = "Port harmonia listens on.";
      };

      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Host or address clients dial to reach this server. Defaults to
          `<machine>.<clan domain>`, which requires that name to resolve on the
          LAN; set an IP to avoid depending on DNS.
        '';
      };

      priority = lib.mkOption {
        type = lib.types.int;
        default = 20;
        description = ''
          Substituter priority, advertised in `nix-cache-info` and applied to the
          URL clients use. Lower wins; cache.nixos.org is 40.
        '';
      };
    };

    perInstance = import ./instance.nix;
  };

  roles.client = {
    description = "A machine that substitutes from the harmonia servers";

    perInstance = import ./client.nix;
  };
}
