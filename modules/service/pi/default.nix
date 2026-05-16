{
  _class = "clan.service";
  manifest.name = "raspberry-pi";
  manifest.readme = builtins.readFile ./README.md;

  roles.pi4b = {
    description = "Raspberry Pi 4B";
    perInstance =
      { ... }:
      {
        nixosModule = ./4b.nix;
      };
  };
}
