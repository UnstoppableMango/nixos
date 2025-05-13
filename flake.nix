{
  description = "UnstoppableMango's NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-24.11";
  };

  outputs = { nixpkgs, ... }:
  let
    system = "x86_64-linux";

    pkgs = import nixpkgs {
      inherit system;
      config = { allowUnfree = true; };
    };

    lib = nixpkgs.lib;

  in {
    nixosConfigurations = {
      hades = lib.nixosSystem {
        inherit system;

        modules = [
          ./system/configuration.nix
        ];
      };
    };
  };
}
