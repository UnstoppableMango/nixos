{
  description = "UnstoppableMango's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    systems.url = "github:nix-systems/default";
    nixos-hardware.url = "github:nixos/nixos-hardware?ref=master";
    flake-parts.url = "github:hercules-ci/flake-parts";

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";

      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        disko.follows = "disko";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    nixvim = {
      url = "github:nix-community/nixvim";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
      inputs.systems.follows = "systems";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    disko = {
      url = "github:nix-community/disko";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dotfiles = {
      url = "github:unstoppablemango/dotfiles";

      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        home-manager.follows = "home-manager";
        nixvim.follows = "nixvim";
        systems.follows = "systems";
        treefmt-nix.follows = "treefmt-nix";
      };
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = import inputs.systems;

      imports = with inputs; [
        flake-parts.flakeModules.modules
        treefmt-nix.flakeModule
        disko.flakeModules.default
        home-manager.flakeModules.home-manager

        ./desktops
        ./hardware
        ./hosts
        ./shells
        ./toolchain
        ./users
      ];

      perSystem =
        {
          inputs',
          pkgs,
          ...
        }:
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
