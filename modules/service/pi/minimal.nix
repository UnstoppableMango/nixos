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

  # The Pi 4's ethernet, PoE HAT and VL805 load no linux-firmware blobs.
  hardware.enableRedistributableFirmware = lib.mkForce false;

  system.disableInstallerTools = true;
  system.tools.nixos-version.enable = true;

  nixpkgs.flake = {
    setNixPath = false;
    setFlakeRegistry = false;
  };

  boot.bcache.enable = false;
  services.lvm.enable = false;

  fonts.fontconfig.enable = false;

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
