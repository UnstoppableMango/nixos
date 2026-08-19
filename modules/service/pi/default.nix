{
  _class = "clan.service";
  manifest.name = "raspberry-pi";
  manifest.readme = builtins.readFile ./README.md;

  roles.pi4b = {
    description = "Raspberry Pi 4B";

    interface =
      { lib, ... }:
      {
        options.nameservers = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [
            "192.168.1.46"
            "192.168.1.47"
          ];
          description = "Nameservers for this Pi 4B.";
        };
      };

    perInstance =
      { settings, ... }:
      {
        nixosModule = {
          imports = [ ./4b.nix ];
          networking.nameservers = settings.nameservers;
        };
      };
  };
}
