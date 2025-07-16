{
  description = "UnstoppableMango's NixOS";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?shallow=1&ref=nixos-24.11";
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

          ({ pkgs, modulesPath, ... }: {
            imports = [ (modulesPath + "/installer/cd-dvd/installation-cd-minimal.nix") ];
            environment.systemPackages = [ pkgs.neovim ];
          })
        ];
      };
    };
  };
}
