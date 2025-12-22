{ inputs, self, ... }:
{
  flake = {
    modules.nixos.hades = ./configuration.nix;
    nixosModules.hades = ./configuration.nix;

    nixosConfigurations.hades = inputs.nixpkgs.lib.nixosSystem {
      modules =
        with inputs;
        [
          nixos-hardware.nixosModules.asus-rog-strix-x570e
          nixos-hardware.nixosModules.common-pc-ssd
          home-manager.nixosModules.home-manager
          disko.nixosModules.disko
        ]
        ++ (with self.modules.nixos; [
          erik
          hades
          ssh
          nix
        ]);
    };
  };
}
