{ inputs, self, ... }:
let
  lib = inputs.nixpkgs.lib;
in
{
  flake.nixosConfigurations."agreus" = lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      {
        imports = with inputs; [
          disko.nixosModules.disko
          home-manager.nixosModules.home-manager
          sops-nix.nixosModules.sops
          # self.modules.nixos.erik
          self.modules.nixos.gnome
          ./configuration.nix
          { hardware.facter.reportPath = ./facter.json; }
        ];
      }
    ];
  };
}
