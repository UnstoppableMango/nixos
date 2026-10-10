{ pkgs, ... }:
{
  imports = [
    ../../modules/ceph
    ../../modules/dns
    ../../modules/nix
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Sandy Bridge box, pollux's twin, and it takes the same grub setup. On the
  # hybrid layout disko lays down, this installs BIOS grub to the disk and an
  # EFI removable-path loader to the ESP, so it boots in either firmware mode.
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
    hostName = "castor";
    useDHCP = false;

    defaultGateway = {
      address = "10.0.69.1";
      interface = "eno1";
    };

    interfaces.eno1 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.13";
          prefixLength = 24;
        }
      ];
    };
  };

  hardware.facter.detected.dhcp.enable = false;

  # enp2s0 is cabled to VLAN 1 and would take a DHCP lease there, adding a
  # second default route. Traffic from VLAN 1 then arrives on eno1 but routes
  # back out enp2s0, and the strict reverse-path filter drops it.
  systemd.network.networks."10-enp2s0" = {
    matchConfig.Name = "enp2s0";
    linkConfig.ActivationPolicy = "down";
  };

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    kubernetes-helm
    ldns
  ];

}
