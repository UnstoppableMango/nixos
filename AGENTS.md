# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Commands

- `make build` - Build configuration for current hostname
- `make hades` / `make agreus` - Build a specific host configuration
- `make check` - Run `nix flake check` locally
- `make fmt` / `make format` - Format all Nix files with nixfmt
- `make update` - Update all flake inputs
- `make system` - Rebuild and switch the local NixOS system (`sudo nixos-rebuild switch`)
- `make agreus-system` - Deploy agreus remotely via nixos-anywhere
- `nix flake check --all-systems` - What CI runs (checks all systems)

## Architecture

This is a NixOS configuration flake using **flake-parts** for modular organization. The key pattern throughout is that each module exports both `flake.modules.nixos.<name>` and `flake.modules.homeManager.<name>` (mirrored as `flake.nixosModules.*` / `flake.homeModules.*`).

### Module System

The flake-parts `flakeModules.modules` extension is used, allowing modules to be referenced via `self.modules.nixos.*` and composed into host configurations.

**How a host is assembled** (see `hosts/hades/default.nix`):
```nix
nixosConfigurations.hades = inputs.nixpkgs.lib.nixosSystem {
  modules = [ nixos-hardware.nixosModules.asus-rog-strix-x570e ]
    ++ (with self.modules.nixos; [ erik gnome hades ssh nixDaemonConfig ]);
};
```

**How a module is exported** (pattern from `desktops/gnome/default.nix`):
```nix
{
  flake.modules.nixos.gnome = gnome;
  flake.nixosModules.gnome = gnome;   # alias for compatibility
}
```

### Directory Layout

- `flake.nix` - Entry point; imports all subdirectories as flake-parts modules
- `hosts/` - Per-host NixOS system definitions (`default.nix` exports the `nixosConfiguration`)
- `users/` - User environment modules; `users/erik/default.nix` wires home-manager config from the `dotfiles` flake input
- `desktops/` - Desktop environment modules (currently GNOME only)
- `hardware/` - Hardware-specific modules (currently NVIDIA config)
- `toolchain/` - System-level toolchain modules (currently nix daemon CPU/IO scheduling)
- `shells/` - Shell service modules (currently SSH)

### Key Flake Inputs

- `nixpkgs` (nixos-unstable) - Package set
- `flake-parts` - Modular flake framework
- `home-manager` - User environment management, integrated via `home-manager.nixosModules.home-manager`
- `dotfiles` - Personal dotfiles flake; provides home-manager modules and overlays consumed in `users/erik/default.nix`
- `disko` - Declarative disk partitioning (each host has a `disk-config.nix`)
- `nixos-hardware` - Hardware-specific module presets
- `nixvim` - Neovim configuration (pulled through `dotfiles`)
- `treefmt-nix` - Formatter config (nixfmt enabled; dprint disabled due to flake check issues)

### Formatter

`nix fmt` uses `treefmt` with only `nixfmt` enabled. The `dprint` formatter is present in config but disabled (`programs.dprint.enable = false`).

## Code Style

- Use `inputs@{ ... }` pattern when binding flake inputs
- Use `with self.modules.nixos; [ ... ]` to compose modules into host configs
- Each functional area gets its own directory with `default.nix` that registers the module via `flake.modules.nixos.*`
- `flake.nixosModules.*` should mirror `flake.modules.nixos.*` as an alias

## Hosts

| Host   | Hardware                   | Notes                              |
| ------ | -------------------------- | ---------------------------------- |
| hades  | ASUS ROG Strix X570-E      | Primary desktop; AMD GPU; BTRFS    |
| agreus | Generic x86_64             | Deployed via nixos-anywhere; facter-based hardware config |

## CI

GitHub Actions runs `nix flake check --all-systems` on nixos-runners with Cachix caching (`unstoppablemango`). The hades build is excluded from CI (too large).
