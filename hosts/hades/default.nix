{ inputs, self, ... }:
{
  flake = {
    modules.nixos.hades = ./configuration.nix;
    nixosModules.hades = ./configuration.nix;

    nixosConfigurations.hades = inputs.nixpkgs.lib.nixosSystem {
      modules = [
        inputs.nixos-hardware.nixosModules.asus-rog-strix-x570e
        inputs.nixos-hardware.nixosModules.common-pc-ssd
        inputs.home-manager.nixosModules.home-manager
      ]
      ++ (with self.modules.nixos; [
        erik
        hades
        ssh
      ]);
    };
  };
}
