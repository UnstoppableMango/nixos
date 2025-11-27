{
  description = "UnstoppableMango's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=release-25.11";
    nixos-hardware.url = "github:nixos/nixos-hardware/master";
    flake-parts.url = "github:hercules-ci/flake-parts";
    home-manager = {
      url = "github:nix-community/home-manager?ref=release-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    dotfiles = {
      url = "github:unstoppablemango/dotfiles";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.home-manager.follows = "home-manager";
    };
    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs =
    inputs@{ self, flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      imports = [
        inputs.treefmt-nix.flakeModule
        inputs.home-manager.flakeModules.home-manager
      ];

      flake = {
        nixosModules = {
          hades = ./hosts/hades/configuration.nix;
        };

        nixosConfigurations.hades = inputs.nixpkgs.lib.nixosSystem {
          modules = [
            inputs.nixos-hardware.nixosModules.asus-rog-strix-x570e
            inputs.nixos-hardware.nixosModules.common-pc-ssd
            self.nixosModules.hades
            inputs.home-manager.nixosModules.home-manager
            {
              home-manager.useGlobalPkgs = true;
              home-manager.useUserPackages = true;
              home-manager.backupFileExtension = "bak";
              home-manager.users.erik = {
                imports = with inputs.dotfiles.homeModules; [
                  erik
                  dconf
                ];
              };
            }
          ];
        };
      };

      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
      perSystem =
        { inputs', pkgs, ... }:
        {
          devShells.default = inputs'.dotfiles.devShells.default;

          treefmt = {
            programs.nixfmt.enable = true;

            programs.dprint = {
              enable = false; # Causing issues with flake checks
              settings.plugins = (
                pkgs.dprint-plugins.getPluginList (
                  plugins: with plugins; [
                    dprint-plugin-json
                    dprint-plugin-markdown
                    g-plane-markup_fmt
                    g-plane-pretty_yaml
                  ]
                )
              );
            };
          };
        };
    };
}
