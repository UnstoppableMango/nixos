---
name: code-review
description: Review checklist for this NixOS flake. Use when reviewing pull requests or diffs that touch .nix files, flake.lock, clan.nix, clan/, machines/, modules/, vars/, or sops/.
---

# Reviewing changes to this repository

This is a personal NixOS configuration built on flake-parts and clan-core.
Machines are declared in `clan.nix`; each machine's NixOS config lives in `machines/<name>/configuration.nix`; shared modules live under `modules/`.
The `rosequartz` Kubernetes cluster is specified in `clan/rosequartz-cluster.nix` and lowered by the `cairn` flake input.

`AGENTS.md` describes the architecture in full. Read it before judging whether a change fits the existing structure.

Everything below is a thing that has actually gone wrong here, or would take a machine or the cluster down.
Prioritize these over generic Nix advice.

## Gates

Formatting is `nix fmt`, which runs treefmt with nixfmt as the only enabled formatter.
Evaluation is `nix flake check`; CI runs `nix flake check --all-systems`, builds `nixosConfigurations.hades...toplevel` with `max-jobs = 1`, and builds `.#rpi-kernel` on an arm64 runner.

Do not assert that a configuration builds or evaluates unless CI has said so. Say what you inspected instead.

## Clan inventory

`clan.nix` owns clan *membership* only, as the `clanMachines` attrset of names.

- Tags and IP addresses come from the `hosts` flake input, not from this repo. A change that hardcodes a tag or address in `clan.nix` is working around the wrong layer; the fix belongs in the hosts flake followed by `nix flake update hosts`.
- `builtins.intersectAttrs` narrows `hosts` to `clanMachines`, and the `unknown` check throws for a name that is not in the hosts flake. Do not suggest removing that check: `intersectAttrs` alone would silently drop a typo'd machine from the inventory.
- Adding a machine means adding it to `clanMachines`, adding `machines/<name>/configuration.nix` and `disk-config.nix`, and usually a Makefile target.

## The rosequartz cluster

Every `rosequartz-*` clan service comes from the `cairn` input. This repo supplies only the cluster spec, `clan/rosequartz-cluster.nix`, wired in via `cairn.clusters.rosequartz` in `flake.nix`.
A PR that hand-writes a `rosequartz-*` inventory instance in `clan.nix` is reintroducing something that was deliberately lowered into cairn.

Two settings in that spec are load-bearing and must not be dropped or "cleaned up":

- `services.pki.generatorPrefix = "rosequartz"`. Cairn defaults this to `"cairn"`. Changing it mints a parallel CA and cert set instead of reusing the existing `vars/{shared,per-machine}/*/rosequartz-*` generators, which takes the cluster down.
- `instancePrefix = "rosequartz-"`, which keeps instance ids stable against the existing vars.

Also treat as intentional, with the reasoning already in the file's comments:

- The five-member etcd quorum (pik8s1, pik8s2, pik8s4-6) with pik8s3 as a worker. A sixth control-plane machine would make the quorum even and buy no extra failure tolerance.
- `services.loadbalancer.machines` pinned to pik8s4-6, because pik8s1 and pik8s2 still have VLAN 1 untagged ports and keepalived would advertise the VIP on the wrong network.
- `services.inoculant.machines` pinned to the control plane rather than defaulting to every machine.
- The VIP `10.0.69.100` is deliberately not in the hosts flake. It is not a machine.

## Generated trees and secrets

`vars/` and `sops/` are produced by clan generators. Hand-edited files there are a blocking finding, as is any plaintext secret, private key, or age key appearing in a diff.

Removing or renaming a var generator orphans the values already deployed to machines. Flag it and ask what the migration is.

## Flake inputs

`flake.lock` bumps belong in their own `deps:` pull request.

Check the `follows` graph when an input changes:

- `dotfiles` must follow `sops-nix`. The module system dedupes imports by path, so two sops-nix store paths would double-declare `options.sops.*` in one home-manager configuration.
- `nixpkgs-stable` is what `clan-core` follows, and `cairn` follows the same `clan-core`. A cairn or clan-core bump that breaks that alignment will produce confusing eval errors far from the change.
- Inputs use flattened dot notation (`inputs.nixpkgs.follows = "nixpkgs";`), not nested attribute sets.

## Module and host style

- Bind flake inputs as `inputs@{ ... }`, and use `with inputs; [ ... ]` in import lists that reference several.
- Each functional area under `modules/` is its own directory with a `default.nix`. Clan service modules go under `modules/service/` and are registered in `clan.nix` under a `@UnstoppableMango/<name>` key.
- `machines/hades/configuration.nix` imports dotfiles' `homeModules.hades`, never `homeModules.erik` as well. The former already contains the latter; importing both doubles it up.
- erik's home-manager surface is owned by the dotfiles repo. Config that belongs there should not be duplicated here.

## Per-host details that look like mistakes but are not

- zeus and castor use grub with `efiSupport` on purpose: legacy BIOS now, with a hybrid layout that survives a firmware switch. castor's firmware mode is unverified, so it takes pollux's dual-mode grub.
- gaea uses systemd-boot.
- pik8s1-6 are aarch64 Raspberry Pi 4Bs. A change that assumes x86_64 breaks the SD image and `rpi-kernel` builds.
- pik8s1 and pik8s2 carry `initialClusterState = "existing"` overrides because they joined an already-formed etcd cluster.
- Network topology lives in `NETWORK.md`. Do not derive VLAN or subnet facts from IPs in `machines/*/configuration.nix`; check `NETWORK.md` and flag it if the change contradicts it.

## Documentation and conventions

- `AGENTS.md` is the source of truth; `CLAUDE.md` points at it. Structural changes should update `AGENTS.md` in the same pull request.
- Pull request titles and commit subjects use Conventional Commits prefixes (`feat:`, `fix:`, `chore:`, `deps:`, `docs:`, `ci:`).
- Markdown in this repo puts one sentence per line and does not use em dashes.
- Comments describe the current state. Avoid "previously", "now", "this was changed to".

## How to comment

Ground every finding in a specific line of the diff, and say what breaks rather than what style rule was missed.
Skip anything nixfmt already enforces.
One comment per distinct issue; do not restate the same point across several files.
If a change looks wrong but the surrounding comments explain the reasoning, read the reasoning before objecting.
