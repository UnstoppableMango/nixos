# Trims the Pis down to what a rosequartz node needs, plus a debugging toolset
# for erik.
{
  lib,
  modulesPath,
  pkgs,
  ...
}:
{
  imports = [ "${modulesPath}/profiles/minimal.nix" ];

  # facter and nixos-raspberrypi's board module turn this on. The Pi 4's
  # ethernet, the PoE HAT and the VL805 USB controller load no blobs from
  # linux-firmware.
  hardware.enableRedistributableFirmware = lib.mkForce false;

  # clan deploys by running switch-to-configuration directly, so nothing on the
  # target calls nixos-rebuild.
  system.disableInstallerTools = true;
  system.tools.nixos-version.enable = true;

  # Builds run against the flake source clan uploads, not the registry entry.
  nixpkgs.flake = {
    setNixPath = false;
    setFlakeRegistry = false;
  };

  # Every Pi's disk-config.nix is plain ext4 and vfat.
  boot.bcache.enable = false;
  services.lvm.enable = false;

  fonts.fontconfig.enable = false;

  # clan's recommended defaults already install dnsutils, tcpdump, curl, jq,
  # htop and git system-wide.
  users.users.erik.packages = with pkgs; [
    conntrack-tools
    cri-tools
    ethtool
    iotop-c # iotop pulls in Python
    kubectl
    lsof
    strace
    sysstat
  ];
}
