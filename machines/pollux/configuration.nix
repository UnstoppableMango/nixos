{ pkgs, ... }:
{
  imports = [
    ../../modules/ceph
    ../../modules/dns
    ../../modules/nix
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Sandy Bridge box that boots in legacy BIOS mode; efiInstallAsRemovable
  # keeps the hybrid layout bootable if the firmware ever switches to UEFI.
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
    hostName = "pollux";
    useDHCP = false;

    defaultGateway = {
      address = "10.0.69.1";
      interface = "eno1";
    };

    interfaces.eno1 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.14";
          prefixLength = 24;
        }
      ];
    };
  };

  hardware.facter.detected.dhcp.enable = false;

  # enp2s0 is cabled to the same LAN as eno1 but has no address. MetalLB's L2
  # speaker answers ARP on every up link, so clients reaching a VIP through
  # enp2s0 hit the strict reverse-path filter and are dropped.
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
