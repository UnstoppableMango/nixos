{ pkgs, ... }:
{
  imports = [
    ../../modules/ceph
    ../../modules/gpu-worker
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot.enable = true;
  };

  # https://nixos.wiki/wiki/Power_Management#systemd_sleep
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  networking = {
    hostName = "vrk8s1";
    useDHCP = false;
  };

  hardware.facter.detected.dhcp.enable = false;

  # Its switch port must be a VLAN 20 access port for this address.
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "10:ff:e0:6f:fe:ed";
    address = [ "10.0.69.16/24" ];
    gateway = [ "10.0.69.1" ];
  };

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
  ];
}
