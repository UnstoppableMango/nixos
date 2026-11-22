{ lib, ... }:
{
  _class = "clan.service";
  manifest.name = "base";
  manifest.readme = builtins.readFile ./README.md;

  roles.default = {
    description = "Configuration every machine in the clan carries";

    interface.options.uptimeUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://10.0.69.103:8443";
      description = "Gatus every machine pushes its disk status to. Null disables the push.";
    };

    perInstance =
      { settings, ... }:
      {
        nixosModule.imports = [
          ../../disk-push
          ../../dns
          ../../gc
          ../../nix
          ../../pki
          (
            { pkgs, ... }:
            {
              environment.systemPackages = [ pkgs.smartmontools ];
            }
          )
          { diskPush.url = settings.uptimeUrl; }
        ];
      };
  };
}
