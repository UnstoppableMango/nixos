{ pkgs, ... }:
{
  imports = [ ./disk-config.nix ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Firmware mode unverified, so take castor's dual-mode grub: BIOS grub on the
  # disk plus an EFI removable-path loader on the ESP.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # https://nixos.wiki/wiki/Power_Management#systemd_sleep
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  networking = {
    hostName = "apollo";
    useDHCP = false;
  };

  hardware.facter.detected.dhcp.enable = false;

  # Matched by MAC rather than interface name. GS724Tv4 g2 must be a VLAN 20
  # access port for this address to be reachable.
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "40:b0:76:d7:f6:06";
    address = [ "10.0.69.12/24" ];
    gateway = [ "10.0.69.1" ];
  };

  # The second onboard NIC is cabled and would take a DHCP lease, adding a
  # second default route the strict reverse-path filter then trips over.
  systemd.network.networks."10-unused" = {
    matchConfig.MACAddress = "40:b0:76:d7:f6:07";
    linkConfig.ActivationPolicy = "down";
  };

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    ldns
  ];
}
