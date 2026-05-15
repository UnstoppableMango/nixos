{ lib, ... }:
{
  _class = "clan.service";
  manifest.name = "raspberry-pi";
  manifest.readme = builtins.readFile ./README.md;

  roles.pi4b = {
    description = "Raspberry Pi 4B";
    perInstance =
      { ... }:
      {
        # WIP: https://clan.lol/docs/25.11/guides/services/community#passing-self-or-pkgs-to-the-module
        nixosModule = lib.modules.importApply ./4b.nix;
      };
  };
}
