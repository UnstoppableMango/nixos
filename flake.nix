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

    nixvim = {
      url = "github:nix-community/nixvim?ref=nixos-25.11";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-parts.follows = "flake-parts";
    };

    treefmt-nix = {
      url = "github:numtide/treefmt-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    dotfiles = {
      url = "github:unstoppablemango/dotfiles";

      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        home-manager.follows = "home-manager";
        nixvim.follows = "nixvim";
        treefmt-nix.follows = "treefmt-nix";
      };
    };
  };

  outputs =
    inputs@{ flake-parts, ... }:
    flake-parts.lib.mkFlake { inherit inputs; } {
      systems = [
        "x86_64-linux"
        "aarch64-linux"
      ];

      imports = with inputs; [
        flake-parts.flakeModules.modules
        treefmt-nix.flakeModule
        home-manager.flakeModules.home-manager

        ./hardware
        ./hosts
        ./shells
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
