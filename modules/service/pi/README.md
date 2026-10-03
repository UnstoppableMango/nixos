# Raspberry Pi Stuff

[4b](./4b.nix)

## Minimal OS

[minimal.nix](./minimal.nix) trims the Pis to what a rosequartz node needs.
It takes the nixpkgs `minimal` profile and also drops linux-firmware, the NixOS installer tools, the pinned nixpkgs registry entry, LVM, bcache and fontconfig.
The erik account gets a debugging toolset: conntrack-tools, cri-tools, ethtool, iotop-c, kubectl, lsof, strace and sysstat.
clan's recommended defaults (dnsutils, tcpdump, curl, jq, htop, git) stay installed system-wide.

## Disks

[disk-config.nix](./disk-config.nix)
