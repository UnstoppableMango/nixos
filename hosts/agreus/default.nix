{ inputs, self, ... }:
let
  mod.imports = with inputs; [
    disko.nixosModules.disko
    home-manager.nixosModules.home-manager
    {
      home-manager.users.erik.imports = [ dotfiles.modules.homeManager.erik ];
    }
    self.modules.nixos.gnome
    ./configuration.nix
    { hardware.facter.reportPath = ./facter.json; }
  ];
in
{
  flake = {
    modules.nixos = mod;
    nixosModules = mod;

    nixosConfigurations."agreus" = inputs.nixpkgs.lib.nixosSystem {
      system = "x86_64-linux";
      modules = [ mod ];
    };
  };
}
