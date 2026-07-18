{ ... }:
{
  flake.nixosConfigurations = {
    # agreus = inputs.nixpkgs.lib.nixosSystem {
    #   specialArgs = { inherit (inputs.dotfiles) inputs; };

    #   modules = with inputs; [
    #     home-manager.nixosModules.home-manager
    #     disko.nixosModules.disko
    #     sops-nix.nixosModules.sops
    #     dotfiles.nixosModules.erik
    #     { nixpkgs.overlays = [ dotfiles.overlays.default ]; }
    #     { hardware.facter.reportPath = ./agreus/facter.json; }

    #     ../desktops
    #     ../shells
    #     ../users/erik
    #     ./agreus/configuration.nix
    #   ];
    # };

    # hades = inputs.nixpkgs.lib.nixosSystem {
    #   specialArgs = { inherit (inputs.dotfiles) inputs; };

    #   modules = with inputs; [
    #     nixos-hardware.nixosModules.asus-rog-strix-x570e
    #     nixos-hardware.nixosModules.common-pc-ssd
    #     home-manager.nixosModules.home-manager
    #     disko.nixosModules.disko
    #     sops-nix.nixosModules.sops
    #     dotfiles.nixosModules.erik
    #     { nixpkgs.overlays = [ dotfiles.overlays.default ]; }

    #     ../modules/desktops
    #     ../modules/shells
    #     ../modules/unifi
    #     ../modules/users/erik
    #     ./hades/configuration.nix
    #   ];
    # };
  };
}
