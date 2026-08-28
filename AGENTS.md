# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Commands

- `make build` - Build configuration for current hostname
- `make hades` / `make agreus` - Build a specific host configuration
- `make check` - Run `nix flake check` locally
- `make fmt` / `make format` - Format all Nix files with nixfmt
- `make update` - Update all flake inputs
- `make system` - Update the local flake and rebuild/switch (`sudo nixos-rebuild switch --flake /etc/nixos --cores 12`)
- `make sd-images` / `make pik8sN-sd` - Build SD card images for Pi nodes
- `make pik8sN-flash` - Flash an SD card image to `$DISK` (default `/dev/sdi`)
- `nix flake check --all-systems` - What CI runs (checks all systems)

## Architecture

This is a NixOS configuration flake using **flake-parts** and **clan-core** for modular organization. All machines (hades, agreus, pollux, castor, pik8s1–6) are clan-managed and configured via `clan.nix`, which holds the inventory (machine tags, service instances) and per-machine `imports`/overrides. Each machine's NixOS config lives under `machines/<name>/configuration.nix`.

### Module System

Plain NixOS modules live under `modules/` and are composed into machine configs via direct `imports`. Clan service modules (role-based, multi-machine) live under `modules/service/` and are registered as clan inventory modules in `clan.nix`.

The `rosequartz` Kubernetes cluster (pik8s4–6 control plane, agreus worker) is **not** defined in this repo. It runs on [cairn](https://github.com/UnstoppableMango/cairn), a library flake that registers one clan service per cluster component (`@UnstoppableMango/{pki,etcd,apiserver,kubelet,loadbalancer,network,kubeconfig,inoculant,coredns,flux}`). `clan.nix` declares a `rosequartz-<component>` instance per service with `module.input = "cairn"`; the services coordinate via clan exports. Cairn's `docs/USAGE.md` and per-service `modules/service/<name>/README.md` are the reference for their options.

Cluster PKI predates cairn, so the `pki` instance sets `roles.node.settings.generatorPrefix = "rosequartz"`, which keeps every existing `vars/{shared,per-machine}/*/rosequartz-*` generator (and the CA behind them) resolving unchanged. Leaving it at cairn's `"cairn"` default would mint a parallel CA and cert set and take the cluster down.

**How hades is assembled** (see `clan.nix` → `machines.hades`):
```nix
hades = {
  clan.core.deployment.requireExplicitUpdate = true;
  imports = with inputs; [
    nixos-hardware.nixosModules.asus-rog-strix-x570e
    nixos-hardware.nixosModules.common-pc-ssd
    home-manager.nixosModules.home-manager
    { nixpkgs.overlays = [ dotfiles.overlays.default ]; }
    ./machines/hades/configuration.nix
  ];
};
```
`machines/hades/configuration.nix` itself imports `../../modules/desktops`, `../../modules/ssh`, and `../../modules/unifi`.

Other machines (agreus, pollux, castor, pik8s1–6) follow the same pattern with a thinner `imports` list, since they don't need desktop/hardware-preset modules.

### Directory Layout

- `flake.nix` - Entry point; imports flake-parts modules; clan config via `./clan.nix`
- `machines/` - Per-machine `configuration.nix` for every host (hades, agreus, pollux, castor, pik8s1–6)
- `modules/` - Shared NixOS modules imported by machine configs:
  - `desktops/` - Desktop environment modules (currently GNOME only)
  - `hardware/` - Hardware-specific modules (currently NVIDIA config)
  - `ssh/` - System-level SSH behavior (currently just `ssh.inhibitSleepOnSsh`, a PAM hook that blocks suspend while an SSH session is open).
    SSH *client* config for erik lives in the dotfiles repo's `modules/ssh`.
  - `unifi/` - UniFi network module
  - `service/` - Clan service modules (`k3s`, `pi`, `trouble`); the rosequartz cluster's services come from the `cairn` input
- Machine metadata lives in the [hosts](https://github.com/UnstoppableMango/hosts) flake's `hosts` output, consumed here and by dotfiles (which follows the same input), so the `internet` clan service and erik's ssh client config never drift apart.
  Each entry is a record (`ip`, `arch`, `tags`).
  Tags are **not** defined in this repo: edit them in the hosts flake and `nix flake update hosts`.
  Every host carries exactly one role tag (`control-plane`, `worker`, `workstation`), and the flake validates that.
- `clan.nix` owns only clan *membership*, as the `clanMachines` attrset of names.
  The hosts flake covers machines this clan does not manage, so `clanMachines` narrows it via `builtins.intersectAttrs`; the resulting `managed` set feeds both `inventory.machines` (tags) and the `internet` instance (addresses).
  Comment an entry out to drop a machine. A name that is not in the hosts flake throws rather than being silently dropped.
- `NETWORK.md` - VLANs, subnets, switch chain, and per-host IP/VLAN assignments, plus the known gaps between configured and reachable addresses.
  Read it before deriving network facts from `machines/*/configuration.nix`, since the physical topology those IPs sit on is recorded nowhere else.
- erik's home-manager surface is owned by the dotfiles repo, and two pieces of it are supplied from here rather than duplicated:
  - `sops.age.keyFile` comes from dotfiles' `modules/sops`, which also imports sops-nix's home-manager module. Nothing here sets it.
  - The rosequartz kubeconfig is generated by dotfiles' `modules/toolchain/kubernetes/rosequartz`. `machines/hades/configuration.nix` supplies only what is repo-local: the CA at `vars/shared/rosequartz-ca/crt/value`, the admin cert/key paths, `currentContext`, and the `sops.templates` sink that keeps `~/.kube/config` a real 0600 file. Shape (contexts, VIP, dex OIDC exec block) is shared with darter.
  - The apiserver VIP `10.0.69.100` is deliberately *not* in the `hosts` flake: it is not a machine, and it is already the default of `dotfiles.kubernetes.rosequartz.server`.
- `clan.nix` - Clan meta-config: cluster name/domain, machine inventory + tags, service instances, per-machine `imports`/overrides
- `vars/` - Clan-generated vars, split into `per-machine/` and `shared/` (SSH keys, password hashes, PKI, state versions)
- `sops/` - SOPS secrets and age keys
- `scripts/` - Utility scripts

### Key Flake Inputs

- `nixpkgs` (nixos-unstable) / `nixpkgs-stable` (nixos-25.11, followed by `clan-core`) - Package sets
- `flake-parts` - Modular flake framework
- `home-manager` - User environment management, integrated via `home-manager.nixosModules.home-manager`
- `dotfiles` - Personal dotfiles flake; provides home-manager modules and overlays.
  Must follow `sops-nix`: dotfiles' `modules/sops` imports sops-nix's home-manager module by path, and the module system dedupes by path, so two sops-nix store paths would double-declare `options.sops.*`.
- `hosts` - Machine inventory (name, ip, arch, role) shared with dotfiles, which follows this input
- `disko` - Declarative disk partitioning (each host has a `disk-config.nix`)
- `nixos-hardware` - Hardware-specific module presets
- `clan-core` (26.05) - Clan cluster management framework; manages all machines via `clan.nix`
- `sops-nix` - SOPS secrets management; followed by both `clan-core` and `dotfiles`
- `nixos-facter` - Hardware detection for facter-based configs
- `nixos-anywhere` - Remote NixOS deployment
- `nixvim` - Neovim configuration (also pulled through `dotfiles`)
- `mynix` - Personal Nix utilities flake
- `gomod2nix` - Go module packaging (used by `mynix`)
- `cairn` (26.05 clan-core, followed) - Kubernetes distribution on Nix and clan; provides every clan service the `rosequartz` cluster runs on. Pulls `a2b` (renders Flux manifests via the real `flux` CLI) and `inoculant` (addon-manifest bootstrap) in as its own inputs.
- `treefmt-nix` - Formatter config (nixfmt enabled)

### Formatter

`nix fmt` uses `treefmt` with only `nixfmt` enabled.

## Code Style

- Use `inputs@{ ... }` pattern when binding flake inputs
- Use `with inputs; [ ... ]` when referencing multiple inputs in a module list
- Modules are plain NixOS modules; compose them into host configs via direct `imports`
- Each functional area under `modules/` gets its own directory with a `default.nix`

## Hosts

| Host          | Hardware              | Notes                                                     |
| ------------- | --------------------- | ---------------------------------------------------------- |
| hades         | ASUS ROG Strix X570-E | Primary desktop; AMD GPU; BTRFS; clan-managed              |
| agreus        | Generic x86_64        | Office mini PC; clan-managed; facter hardware config; rosequartz worker |
| pollux        | Sandy Bridge i5, legacy BIOS | Basement rack server; clan-managed; facter hardware config; rosequartz worker |
| castor        | Sandy Bridge i5-2500, UEFI  | Basement rack server; pollux's twin; rosequartz worker; NixOS on disk, never booted into it |
| pik8s1–6      | Raspberry Pi 4B       | k8s cluster nodes; clan-managed; aarch64; pik8s1–3 are k3s, pik8s4–6 are the rosequartz control-plane |

## Sub-Agent Guidance

Read additional AGENTS.md files when working in these areas:

- **Clan services** (`modules/service/`): read `./modules/service/AGENTS.md`
- **Rosequartz / Kubernetes**: the services live in the `cairn` input, not this repo. Read cairn's `AGENTS.md`, `docs/ARCHITECTURE.md`, and `modules/service/AGENTS.md`, plus the `rosequartz-*` instances in `clan.nix`.

## CI

`.github/workflows/ci.yml` runs two jobs on push/PR to `main`, both with Cachix caching (`unstoppablemango`):
- `build` (ubuntu-latest): `nix flake check` + `nix build .#nixosConfigurations.hades...toplevel`, with `max-jobs = 1` to avoid OOM on the runner's limited RAM
- `rpi-kernel` (ubuntu-24.04-arm): `nix build .#rpi-kernel`
