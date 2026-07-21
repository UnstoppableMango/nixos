# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Commands

- `make build` - Build configuration for current hostname
- `make hades` / `make agreus` - Build a specific host configuration
- `make check` - Run `nix flake check` locally
- `make fmt` / `make format` - Format all Nix files with nixfmt
- `make update` - Update all flake inputs
- `make system` - Update the local flake and rebuild/switch (`sudo nixos-rebuild switch --flake /etc/nixos --cores 12`)
- `make agreus-system` - Deploy agreus remotely via nixos-anywhere with facter hardware detection
- `nix flake check --all-systems` - What CI runs (checks all systems)

## Architecture

This is a NixOS configuration flake using **flake-parts** and **clan-core** for modular organization. Machines are configured via two parallel structures:
- `hosts/` — direct `nixpkgs.lib.nixosSystem` definitions (currently hades only)
- `machines/` — clan-managed machines (agreus, pik8s cluster nodes), configured via `clan.nix`

### Module System

Plain NixOS modules live under `modules/` and are composed into host configs via direct `imports`.

**How hades is assembled** (see `hosts/default.nix`):
```nix
hades = inputs.nixpkgs.lib.nixosSystem {
  specialArgs = { inherit (inputs.dotfiles) inputs; };
  modules = with inputs; [
    nixos-hardware.nixosModules.asus-rog-strix-x570e
    nixos-hardware.nixosModules.common-pc-ssd
    home-manager.nixosModules.home-manager
    disko.nixosModules.disko
    sops-nix.nixosModules.sops
    dotfiles.nixosModules.erik
    { nixpkgs.overlays = [ dotfiles.overlays.default ]; }
    ../modules/desktops
    ../modules/shells
    ../modules/users/erik
    ./hades/configuration.nix
  ];
};
```

Clan-managed machines (agreus, pik8s nodes) are configured in `clan.nix` via the clan inventory system; their NixOS config lives under `machines/<name>/configuration.nix` and clan service modules under `modules/service/`.

### Directory Layout

- `flake.nix` - Entry point; imports flake-parts modules and `./hosts`; clan config via `./clan.nix`
- `hosts/` - Per-host NixOS system definitions; `default.nix` exports `flake.nixosConfigurations`; currently only hades
- `machines/` - Per-machine config for clan-managed nodes (agreus, pik8s1–6)
- `modules/` - Shared NixOS modules imported by host configs:
  - `desktops/` - Desktop environment modules (currently GNOME only)
  - `hardware/` - Hardware-specific modules (currently NVIDIA config)
  - `shells/` - Shell service modules (currently SSH)
  - `users/` - User environment modules; `users/erik/default.nix` wires home-manager config from the `dotfiles` input
  - `service/` - Clan service modules (`k3s`, `pi`)
- `clan.nix` - Clan meta-config: cluster name/domain, inventory of clan-managed machines and service instances
- `vars/` - Per-machine variables (SSH keys, password hashes, state versions)
- `sops/` - SOPS secrets and age keys
- `scripts/` - Utility scripts

### Key Flake Inputs

- `nixpkgs` (nixos-unstable) - Package set
- `flake-parts` - Modular flake framework
- `home-manager` - User environment management, integrated via `home-manager.nixosModules.home-manager`
- `dotfiles` - Personal dotfiles flake; provides home-manager modules and overlays consumed in `modules/users/erik/default.nix`
- `disko` - Declarative disk partitioning (each host has a `disk-config.nix`)
- `nixos-hardware` - Hardware-specific module presets
- `clan-core` (v25.11) - Clan cluster management framework; manages agreus and pik8s machines
- `sops-nix` - SOPS secrets management
- `nixos-facter` - Hardware detection for facter-based configs
- `nixos-anywhere` - Remote NixOS deployment
- `nixvim` - Neovim configuration (also pulled through `dotfiles`)
- `mynix` - Personal Nix utilities flake
- `treefmt-nix` - Formatter config (nixfmt enabled)

### Formatter

`nix fmt` uses `treefmt` with only `nixfmt` enabled.

## Code Style

- Use `inputs@{ ... }` pattern when binding flake inputs
- Use `with inputs; [ ... ]` when referencing multiple inputs in a module list
- Modules are plain NixOS modules; compose them into host configs via direct `imports`
- Each functional area under `modules/` gets its own directory with a `default.nix`

## Hosts

| Host           | Hardware              | Notes                                                |
| -------------- | --------------------- | ---------------------------------------------------- |
| hades          | ASUS ROG Strix X570-E | Primary desktop; AMD GPU; BTRFS; direct nixosSystem  |
| agreus         | Generic x86_64        | Office mini PC; clan-managed; facter hardware config |
| pik8s1–3, 5–6  | Raspberry Pi 4B       | k8s cluster nodes; clan-managed; aarch64             |

## Sub-Agent Guidance

Read additional AGENTS.md files when working in these areas:

- **Clan services** (`modules/service/`): read `./modules/service/AGENTS.md`
- **Rosequartz / Kubernetes**: read `./modules/service/rosequartz/AGENTS.md`

## CI

GitHub Actions runs `nix flake check --all-systems` on nixos-runners with Cachix caching (`unstoppablemango`). The hades build runs too, with `max-jobs = 1` set to avoid OOM from parallel derivation builds on the runner's limited RAM.
