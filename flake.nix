{
  description = "UnstoppableMango's NixOS configuration";

  inputs = {
    nixpkgs.url = "github:nixos/nixpkgs?ref=nixos-unstable";
    nixpkgs-stable.url = "github:nixos/nixpkgs?ref=nixos-25.11";
    systems.url = "github:nix-systems/default";
    nixos-hardware.url = "github:nixos/nixos-hardware?ref=master";
    flake-parts.url = "github:hercules-ci/flake-parts";

    flake-utils = {
      url = "github:numtide/flake-utils";
      inputs.systems.follows = "systems";
    };

    home-manager = {
      url = "github:nix-community/home-manager";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    nixos-anywhere = {
      url = "github:nix-community/nixos-anywhere";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        disko.follows = "disko";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    clan-core = {
      url = "https://git.clan.lol/clan/clan-core/archive/25.11.tar.gz";
      inputs = {
        nixpkgs.follows = "nixpkgs-stable";
        systems.follows = "systems";
        flake-parts.follows = "flake-parts";
        disko.follows = "disko";
        sops-nix.follows = "sops-nix";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    nixos-facter = {
      url = "github:nix-community/nixos-facter";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.systems.follows = "systems";
      inputs.treefmt-nix.follows = "treefmt-nix";
      inputs.disko.follows = "disko";
    };

    nixvim = {
      url = "github:nix-community/nixvim";
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

    sops-nix = {
      url = "github:mic92/sops-nix";
      inputs.nixpkgs.follows = "nixpkgs";
    };

    gomod2nix = {
      url = "github:nix-community/gomod2nix";
      inputs.nixpkgs.follows = "nixpkgs";
      inputs.flake-utils.follows = "flake-utils";
    };

    mynix = {
      url = "github:unstoppablemango/nix";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        gomod2nix.follows = "gomod2nix";
        systems.follows = "systems";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    a2b = {
      url = "github:UnstoppableMango/a2b";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    inoculant = {
      url = "github:UnstoppableMango/inoculant";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        systems.follows = "systems";
        flake-parts.follows = "flake-parts";
        treefmt-nix.follows = "treefmt-nix";
      };
    };

    dotfiles = {
      url = "github:unstoppablemango/dotfiles";
      inputs = {
        nixpkgs.follows = "nixpkgs";
        flake-parts.follows = "flake-parts";
        flake-utils.follows = "flake-utils";
        clan-core.follows = "clan-core";
        gomod2nix.follows = "gomod2nix";
        home-manager.follows = "home-manager";
        mynix.follows = "mynix";
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
        clan-core.flakeModules.default

        ./apps/rosequartz.nix
      ];

      clan = {
        imports = [ (import ./clan.nix { inherit inputs; }) ];
        specialArgs = { inherit inputs; };
      };

      perSystem =
        {
          inputs',
          lib,
          pkgs,
          system,
          ...
        }:
        {
          _module.args.pkgs = import inputs.nixpkgs {
            inherit system;
            config.allowUnfree = true;
            overlays = [
              inputs.dotfiles.overlays.default
            ];
          };

          packages = lib.optionalAttrs (system == "aarch64-linux") {
            rpi-kernel =
              # Copy the kernelPackages config so we can build + cache the aarch64 kernel
              # https://github.com/NixOS/nixos-hardware/blob/master/raspberry-pi/4/default.nix#L31-L33
              (pkgs.linuxPackagesFor (
                pkgs.callPackage "${inputs.nixos-hardware}/raspberry-pi/common/kernel.nix" {
                  rpiVersion = 4;
                }
              )).kernel;
          };

          devShells = {
            inherit (inputs'.dotfiles.devShells) default;
          };

          treefmt = {
            programs.nixfmt.enable = true;
          };
        };
    };
}
