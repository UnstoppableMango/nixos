# NixOS

My NixOS configurations, managed as a flake with [flake-parts](https://flake.parts) and [clan-core](https://clan.lol).

## Hosts

| Host    | Hardware              | Path                                                       | Notes                          |
| ------- | ---------------------- | ----------------------------------------------------------- | ------------------------------- |
| hades   | ASUS ROG Strix X570-E  | [machines/hades/configuration.nix](./machines/hades/configuration.nix)     | Primary desktop; AMD GPU; BTRFS |
| agreus  | Generic x86_64          | [machines/agreus/configuration.nix](./machines/agreus/configuration.nix)   | Office mini PC; clan-managed    |
| pik8s1–6 | Raspberry Pi 4B        | [machines/pik8s\*/configuration.nix](./machines)             | k3s cluster nodes; clan-managed |

`hades` and `agreus` are configured directly; the pik8s nodes and agreus are also wired into the clan inventory in [clan.nix](./clan.nix).

## Usage

```sh
make build          # Build configuration for the current hostname
make hades          # Build the hades configuration
make agreus         # Build the agreus configuration
make check          # Run `nix flake check`
make fmt            # Format all Nix files with nixfmt
make update         # Update all flake inputs
make system         # Update the local flake and rebuild/switch
```

See the [Makefile](./Makefile) for additional targets (Raspberry Pi SD card images, flashing, kubeconfig retrieval).

## Layout

- `flake.nix` - Entry point; clan config lives in [clan.nix](./clan.nix)
- `machines/` - Per-machine NixOS configuration
- `modules/` - Shared NixOS modules (desktops, hardware, shells, clan services)
- `vars/` - Per-machine variables (SSH keys, password hashes, state versions)
- `sops/` - SOPS secrets and age keys
- `scripts/` - Utility scripts

More detail on the module system and architecture lives in [AGENTS.md](./AGENTS.md).
