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

  # The living room's switch is unmanaged, so vrk8s1 tags VLAN 20 itself and the
  # managed port feeding that switch carries it tagged. The NIC takes no address
  # of its own. Type keeps the match off the VLAN, which shares the NIC's MAC.
  systemd.network.netdevs."20-cluster" = {
    netdevConfig = {
      Kind = "vlan";
      Name = "cluster";
    };
    vlanConfig.Id = 20;
  };

  systemd.network.networks."10-lan" = {
    matchConfig = {
      MACAddress = "10:ff:e0:6f:fe:ed";
      Type = "ether";
    };
    vlan = [ "cluster" ];
    linkConfig.RequiredForOnline = "carrier";
  };

  systemd.network.networks."20-cluster" = {
    matchConfig.Name = "cluster";
    address = [ "10.0.69.16/24" ];
    gateway = [ "10.0.69.1" ];
  };

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
  ];
}
