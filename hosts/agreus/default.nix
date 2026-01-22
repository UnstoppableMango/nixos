{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
in
{
  flake.nixosConfigurations."agreus" = lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      {
        nixpkgs.overlays = with inputs; [
          dotfiles.overlays.default
        ];

        imports = with inputs; [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          {
            home-manager.users.erik.imports = [ dotfiles.modules.homeManager.erik ];
          }
          self.modules.nixos.gnome
          ./configuration.nix
          { hardware.facter.reportPath = ./facter.json; }
        ];
      }
    ];
  };
}
