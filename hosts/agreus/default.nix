{ inputs, self, ... }:
{
  flake.nixosConfigurations."agreus" = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";
    modules = [
      inputs.disko.nixosModules.disko
      self.modules.nixos.gnome
      ./configuration.nix
      { hardware.facter.reportPath = ./facter.json; }
    ];
  };
}
