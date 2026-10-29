# AGENTS.md

This file provides guidance to AI agents when working with code in this repository.

## Commands

- `make build` - Build configuration for current hostname
- `make hades` / `make agreus` - Build a specific host configuration
- `make iso` - Build a generic hybrid BIOS/UEFI installer ISO (`bin/installer.iso`) for onboarding a machine with `clan machines install`
- `make <host>-iso` - Build an x86_64 host's own config as an installer ISO; it runs that host's services on the live image
- `make check` - Run `nix flake check` locally
- `make fmt` / `make format` - Format all Nix files with nixfmt
- `make update` - Update all flake inputs
- `make system` - Update the local flake and rebuild/switch (`sudo nixos-rebuild switch --flake /etc/nixos --cores 12`)
- `make sd-images` / `make pik8sN-sd` - Build Pi images (nixos-raspberrypi's sd-image, 1024 MiB firmware partition)
- `make pik8sN-flash` - Write a Pi image to `$DISK` (default `/dev/sdi`). The Pis boot from a USB SSD with no SD card, so `$DISK` is the SSD attached to the workstation.
- `nix flake check --all-systems` - What CI runs (checks all systems)

## Architecture

This is a NixOS configuration flake using **flake-parts** and **clan-core** for modular organization. All machines (hades, agreus, pollux, castor, zeus, gaea, iris, pik8s1–9) are clan-managed and configured via `clan.nix`, which holds the inventory (machine tags, service instances) and per-machine `imports`/overrides. Each machine's NixOS config lives under `machines/<name>/configuration.nix`.

### Module System

Plain NixOS modules live under `modules/` and are composed into machine configs via direct `imports`. Clan service modules (role-based, multi-machine) live under `modules/service/` and are registered as clan inventory modules in `clan.nix`.
Modules every machine needs (`modules/dns`, `modules/gc`, `modules/nix`, `modules/pki`) are not imported per machine: the `base` instance in `clan.nix` attaches them to every inventory member through its `tags.all` role, the same way the `clan-cache` instance attaches `modules/cache`.

The `rosequartz` Kubernetes cluster (control plane and workers listed in `clan/rosequartz-cluster.nix`) is **not** defined in this repo. It runs on [cairn](https://github.com/UnstoppableMango/cairn), a library flake that registers one clan service per cluster component (`@UnstoppableMango/{pki,etcd,apiserver,kubelet,loadbalancer,network,kubeconfig,inoculant,coredns,flux}`). `clan.nix` declares a `rosequartz-<component>` instance per service with `module.input = "cairn"`; the services coordinate via clan exports. Cairn's `docs/USAGE.md` and per-service `modules/service/<name>/README.md` are the reference for their options.

Cluster PKI predates cairn, so the `pki` instance sets `roles.node.settings.generatorPrefix = "rosequartz"`, which keeps every existing `vars/{shared,per-machine}/*/rosequartz-*` generator (and the CA behind them) resolving unchanged. Leaving it at cairn's `"cairn"` default would mint a parallel CA and cert set and take the cluster down.

**How hades is assembled** (see `clan.nix` → `machines.hades`):
```nix
hades = {
  clan.core.deployment.requireExplicitUpdate = true;
  clan.core.networking.targetHost = "root@${managed.hades.ip}";
  imports = with inputs; [
    nixos-hardware.nixosModules.asus-rog-strix-x570e
    nixos-hardware.nixosModules.common-pc-ssd
    { nixpkgs.overlays = [ dotfiles.overlays.default ]; }
    ./machines/hades/configuration.nix
  ];
};
```
`machines/hades/configuration.nix` itself imports `../../modules/desktops`, `../../modules/ssh`, and `../../modules/unifi`.

Other machines (agreus, pollux, castor, zeus, gaea, iris, pik8s1–9) follow the same pattern with a thinner `imports` list, since they don't need desktop/hardware-preset modules.

### Directory Layout

- `flake.nix` - Entry point; imports flake-parts modules; clan config via `./clan.nix`
- `machines/` - Per-machine `configuration.nix` for every host (hades, agreus, pollux, castor, zeus, gaea, iris, pik8s1–9)
- `modules/` - Shared NixOS modules imported by machine configs:
  - `brave/` - Brave enterprise policy at `/etc/brave/policies/managed/`, currently just the `thecluster` managed-bookmarks folder.
    Brave itself is installed by the dotfiles repo's home-manager configuration; policy lives in `/etc`, which home-manager cannot write, so it is supplied here.
    The bookmark list is a plain data file (`modules/brave/bookmarks.nix`) shared with the `brave-bookmarks-policy` package in `flake.nix`, so darter, which is not a clan machine and has no Nix-managed `/etc`, installs the same file with
    `sudo install -Dm644 "$(nix build --no-link --print-out-paths github:UnstoppableMango/nixos#brave-bookmarks-policy)" /etc/brave/policies/managed/bookmarks.json`.
    `certificates.nix` is the `CACertificates` policy carrying the same root as `pki/`, since Chromium on Linux ignores the system bundle; darter installs it the same way from `#brave-certificates-policy` as `certificates.json`.
  - `pki/` - Trusts the UnMango Root CA G2 from [pki](https://github.com/UnstoppableMango/pki) system-wide; `ca.pem` is a copy of that repo's `certs/ca.pem`.
    Every `*.thecluster.lan` cert chains to it through UnMango Private CA 01.
    `thecluster-lan-nginx-ca.pem` is the pre-ceremony CA, trusted on every machine alongside it until the-cluster's gateway serves the new chain.
  - `ceph-cluster-network/` - Ceph's cluster network on the SFP+ aggregator (`cephClusterNetwork.*`): a macvlan shim holding the host's `10.0.70.0/24` address, and multus as the host CNI plugin wrapping flannel, so Rook's OSD pods get a macvlan interface from the host's `host-local` range.
    multus runs from NixOS rather than its DaemonSet because the kubelet module relinks `/opt/cni/bin` on every start and `/etc/cni/net.d` is a store path.
    Addresses per host are in `NETWORK.md`.
  - `ci-limits/` - Memory and CPU limits for hosts running Hercules CI builds alongside rook-ceph pods (zeus, gaea).
    Puts nix-daemon, the Hercules agents and harmonia in a capped `ci.slice`, sets nix `max-jobs`/`cores`, and reserves the slice ceiling from the kubelet.
    Each host sizes it through `ciLimits.*` in its `configuration.nix`; per-agent `concurrentTasks` is set on the hercules-ci instances in `clan.nix`.
  - `ci-idle/` - Hercules CI agents on hades, in a low-weight `ci.slice` whose `MemoryHigh` drops to `ciIdle.activeMemoryHigh` while a graphical session is active and unlocked.
    The agents' evaluator heap is never returned to the kernel, so zram is enabled for the kernel to reclaim it into.
    nix-daemon stays outside the slice, since it also runs the desktop user's builds.
  - `gc/` - Weekly `nh clean` (keeps the last 5 generations and anything under 14 days), attached to every machine by the `base` instance.
    On agent machines (gaea, hades, zeus) the `hercules-ci-agent` service stops the agents while it runs, since a collection mid-task can delete paths the task still needs.
  - `desktops/` - Desktop environment modules (currently GNOME only)
  - `hardware/` - Hardware-specific modules (currently NVIDIA config)
  - `htpc/` - Kodi under the cage kiosk compositor on agreus, started and stopped with the TV's power.
    The TV keeps HDMI hotplug asserted in standby, so `htpc-tv-power` polls the TV's network API instead, which stops answering in standby; a game controller connecting also starts Kodi.
    The poll crosses from VLAN 20 to VLAN 1, so it depends on the pfSense rule listed in `NETWORK.md`.
    Capped in kodi's `user-1001.slice` and not reserved from the kubelet, so pods keep the memory while Kodi is not running.
    Media sources are WebDAV shares from copyparty in the-cluster (`apps/media`), written to a store-linked `sources.xml`, so sources added in Kodi's UI do not persist.
  - `kiosk/` - A web page in Firefox kiosk mode under cage, always on, on pik8s3's display, where it shows the `uptime/` status page.
    Its user slice is capped at `kiosk.memoryMax`; on a Kubernetes node, reserve that much from the kubelet.
  - `uptime/` - Gatus on pik8s3, outside rosequartz, so something still reports the cluster down while it is down.
    It checks the apiserver VIP, each apiserver and etcd member, the gateway, every resolver, and the services listed in `uptime.services` (Nextcloud's `status.php`), and pings every clan machine; `clan.nix` fills the machine, apiserver and etcd lists from the inventory and `clan/rosequartz-cluster.nix`.
    The status page is on port 8080, open on the LAN. No alerting is configured.
  - `pihole/` - Pi-hole on pik8s1, pik8s2 and pik8s6, outside rosequartz, so the LAN keeps a filtering resolver while the cluster is down.
    Its config is read-only NixOS, so external-dns cannot write `thecluster.lan` records into it the way it does for the in-cluster piholes; the whole zone is a wildcard to the rosequartz gateway (`pihole.gatewayAddress`) instead.
    The web UI password is the shared `pihole-admin` var. Machines still resolve through the in-cluster piholes until `modules/dns` points at these.
  - `ssh/` - System-level SSH behavior (currently just `ssh.inhibitSleepOnSsh`, a PAM hook that blocks suspend while an SSH session is open).
    SSH *client* config for erik lives in the dotfiles repo's `modules/ssh`.
  - `unifi/` - UniFi network module
  - `service/` - Clan service modules (`base`, `build-host`, `harmonia`, `hercules-ci-agent`, `k3s`, `pi`, `trouble`); the rosequartz cluster's services come from the `cairn` input.
    The `build-host` service makes the Pis build on gaea (aarch64 under binfmt), with a gaea root key the Pis trust, so `clan machines update pik8sN` never compiles on a Pi.
    Deploy gaea before the Pis whenever its substituters or binfmt change.
    The `pi` service also trims the Pis to a minimal OS (`modules/service/pi/minimal.nix`): no linux-firmware, installer tools or docs, plus a debugging toolset for erik.
- Machine metadata lives in the [hosts](https://github.com/UnstoppableMango/hosts) flake's `hosts` output, consumed here and by dotfiles (which follows the same input), so the `internet` clan service and erik's ssh client config never drift apart.
  Each entry is a record (`ip`, `arch`, `tags`).
  Tags are **not** defined in this repo: edit them in the hosts flake and `nix flake update hosts`.
  Every host carries exactly one role tag (`control-plane`, `worker`, `workstation`), and the flake validates that.
- `clan.nix` owns only clan *membership*, as the `clanMachines` attrset of names.
  The hosts flake covers machines this clan does not manage, so `clanMachines` narrows it via `builtins.intersectAttrs`; the resulting `managed` set feeds both `inventory.machines` (tags) and the `internet` instance (addresses).
  Comment an entry out to drop a machine. A name that is not in the hosts flake throws rather than being silently dropped.
- `NETWORK.md` - VLANs, subnets, switch chain, and per-host IP/VLAN assignments, plus the known gaps between configured and reachable addresses.
  Read it before deriving network facts from `machines/*/configuration.nix`, since the physical topology those IPs sit on is recorded nowhere else.
- Home directories on hades are standalone Home Manager installs from the dotfiles repo (`erik@hades`, `tz@hades`), not NixOS modules here.
  This repo owns the machine and the system accounts (the `erik` and `tz` users instances in `clan.nix`), and installs the `home-manager` CLI for tz so that account can bootstrap its home.
  - The rosequartz kubeconfig and its admin identity live in dotfiles' `hosts/hades.nix` and `modules/kubernetes/rosequartz`.
  - The apiserver VIP `10.0.69.100` is deliberately *not* in the `hosts` flake: it is not a machine, and it is already the default of `dotfiles.kubernetes.rosequartz.server`.
- `clan.nix` - Clan meta-config: cluster name/domain, machine inventory + tags, service instances, per-machine `imports`/overrides
- `vars/` - Clan-generated vars, split into `per-machine/` and `shared/` (SSH keys, password hashes, PKI, state versions)
- `sops/` - SOPS secrets and age keys
- `scripts/` - Utility scripts

### Key Flake Inputs

- `nixpkgs` (nixos-unstable) / `nixpkgs-stable` (nixos-25.11, followed by `clan-core`) - Package sets
- `flake-parts` - Modular flake framework
- `home-manager` - Not imported by any machine; it exists so `dotfiles` can follow it.
- `dotfiles` - Personal dotfiles flake; hades takes its `overlays.default`.
- `hercules-ci-agent` - Provides `nixosModules.multi-agent-service`, which the `hercules-ci-agent` clan service imports to run one agent per Hercules CI account on zeus and gaea.
  Its nixpkgs is not followed, so the agent package matches what upstream caches.
- `hosts` - Machine inventory (name, ip, arch, role) shared with dotfiles, which follows this input
- `disko` - Declarative disk partitioning (each host has a `disk-config.nix`)
- `nixos-hardware` - Hardware-specific module presets (hades)
- `nixos-raspberrypi` - Raspberry Pi kernel, firmware, `config.txt` and the `kernel` bootloader for pik8s1-9, via `modules/service/pi/4b.nix`. It keeps its own pinned nixpkgs rather than following ours, so the kernel comes prebuilt from nixos-raspberrypi.cachix.org (a substituter on every machine via `modules/cache`); `4b.nix` adds the two kernel attributes our 26.11 NixOS reads that its 26.05 kernel lacks.
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
| hades         | ASUS ROG Strix X570-E | Primary desktop; AMD GPU; BTRFS; clan-managed; Hercules CI agent for both accounts at two tasks each |
| agreus        | Generic x86_64        | Office mini PC; clan-managed; facter hardware config; rosequartz worker; HTPC (Kodi, follows the TV's power) |
| pollux        | Sandy Bridge i5, legacy BIOS | Basement rack server; clan-managed; facter hardware config; rosequartz worker |
| castor        | Sandy Bridge i5-2500  | Basement rack server; pollux's twin; rosequartz worker; firmware mode unverified, so it takes pollux's dual-mode grub |
| zeus          | Dual Xeon E5-2670 tower, legacy BIOS | Basement tower; clan-managed; rosequartz worker; grub with `efiSupport` so the hybrid layout survives a firmware switch |
| gaea          | EPYC 7502 rack box, UEFI | Basement rack server; clan-managed; rosequartz worker; systemd-boot |
| iris          | Dell R410, UEFI       | Basement rack server; clan-managed; rosequartz worker; systemd-boot; NIC names and install disk unverified |
| apollo        | ASUS board, firmware mode unverified | Basement server; clan-managed; rosequartz worker; takes castor's dual-mode grub |
| pik8s1–9      | Raspberry Pi 4B       | k8s cluster nodes; clan-managed; aarch64; pik8s7–9 (8GB) are the rosequartz control plane and pik8s4–5 (4GB) are etcd-only members (five etcd members in all); pik8s3 has left rosequartz and runs the Gatus uptime checker (`modules/uptime`), shown on its display; pik8s1, pik8s2 and pik8s6 have left rosequartz and run Pi-hole (`modules/pihole`) |

## Sub-Agent Guidance

Read additional AGENTS.md files when working in these areas:

- **Clan services** (`modules/service/`): read `./modules/service/AGENTS.md`
- **Rosequartz / Kubernetes**: the services live in the `cairn` input, not this repo. Read cairn's `AGENTS.md`, `docs/ARCHITECTURE.md`, and `modules/service/AGENTS.md`, plus the `rosequartz-*` instances in `clan.nix`.

## CI

`.github/workflows/ci.yml` runs one job, `build`, on push/PR to `main`, with Cachix caching (`unstoppablemango`): `nix flake check` + `nix build .#nixosConfigurations.hades...toplevel` on the `thecluster` runner.

## Agent skills

### Issue tracker

Issues are tracked in this repo's GitHub Issues. See `docs/agents/issue-tracker.md`.

### Triage labels

The five default triage labels, each named after its role (`needs-triage`, `needs-info`, `ready-for-agent`, `ready-for-human`, `wontfix`). See `docs/agents/triage-labels.md`.

### Domain docs

Single-context: one `CONTEXT.md` and `docs/adr/` at the repo root. See `docs/agents/domain.md`.
