# nixos

[![CI](https://github.com/UnstoppableMango/nixos/actions/workflows/ci.yml/badge.svg)](https://github.com/UnstoppableMango/nixos/actions/workflows/ci.yml)

My NixOS configurations for every machine I run, from a desktop to a rack of servers to a pile of Raspberry Pis.

Built as a flake with [flake-parts](https://flake.parts), with all machines managed as a single clan via [clan-core](https://clan.lol).
The `rosequartz` Kubernetes cluster that most of these machines belong to is defined in [cairn](https://github.com/UnstoppableMango/cairn) and wired up here through clan service instances.

## Hosts

| Host | Address | Hardware | Role |
| --- | --- | --- | --- |
| hades | `192.168.1.69`, `10.0.69.69` | ASUS ROG Strix X570-E, AMD GPU, BTRFS | Desktop workstation |
| agreus | `10.0.69.187` | Generic x86_64 mini PC | rosequartz worker |
| pollux | `10.0.69.14` | Sandy Bridge i5, legacy BIOS | rosequartz worker |
| castor | `10.0.69.13` | Sandy Bridge i5-2500, pollux's twin | rosequartz worker |
| zeus | `10.0.69.10` | Dual Xeon E5-2670 tower, legacy BIOS | rosequartz worker |
| gaea | `10.0.69.11` | EPYC 7502 rack box, UEFI | rosequartz worker |
| pik8s1-3 | `192.168.1.101-103` | Raspberry Pi 4B | k3s nodes |
| pik8s4-6 | `10.0.69.104-106` | Raspberry Pi 4B | rosequartz control plane |

Machine metadata (address, arch, role tags) comes from the shared [hosts](https://github.com/UnstoppableMango/hosts) flake rather than being defined here.
Physical topology, VLANs, and switch ports are in [NETWORK.md](./NETWORK.md).

## Usage

```sh
make build       # Build the configuration for the current hostname
make hades       # Build a named host (hades, agreus, pollux, castor, zeus, gaea)
make check       # nix flake check
make fmt         # Format every Nix file with nixfmt
make update      # Update all flake inputs
make system      # Update the local flake and rebuild/switch
```

Raspberry Pi images:

```sh
make sd-images      # Build SD card images for all six Pis
make pik8s4-sd      # Build one image into bin/
make pik8s4-flash   # dd that image to $DISK (default /dev/sdi)
```

See the [Makefile](./Makefile) for the rest.

## Layout

- `flake.nix` - Entry point, wires up flake-parts and clan
- `clan.nix` - Clan membership, inventory tags, service instances, per-machine imports
- `machines/` - One `configuration.nix` and `disk-config.nix` per host
- `modules/` - Shared NixOS modules (`desktops`, `hardware`, `ceph`, `ssh`, `unifi`) and clan services under `service/`
- `clan/` - Cluster-level clan configuration
- `vars/` - Clan-generated vars, per-machine and shared (SSH keys, password hashes, PKI)
- `sops/` - SOPS secrets and age keys
- `scripts/` - Utility scripts
- `NETWORK.md` - VLANs, subnets, switch chain, per-host IP assignments

My home-manager configuration lives in a separate dotfiles flake and is pulled in as an input.

## Notes for agents

[AGENTS.md](./AGENTS.md) covers the module system, how each host is assembled, the flake inputs, and the constraints that are easy to break.
Read it before changing anything structural.

## License

[MIT](./LICENSE)
