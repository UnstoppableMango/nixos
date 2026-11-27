{ pkgs, ... }:
{
  imports = [
    ../../modules/ceph
    ../../modules/ceph-cluster-network
    ../../modules/dns
    ../../modules/nix
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Without reservations the OSDs contend with the kernel.
  services.kubernetes.kubelet.extraConfig = {
    systemReserved = {
      cpu = "2";
      memory = "4Gi";
    };
    kubeReserved = {
      cpu = "1";
      memory = "2Gi";
    };
    evictionHard."memory.available" = "2Gi";
  };

  # Legacy BIOS only: the firmware's UEFI path crashes on a fallback BOOTX64.EFI.
  boot.loader.grub.enable = true;

  # https://nixos.wiki/wiki/Power_Management#systemd_sleep
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  # bnx2x loads the SFP+ card's firmware from linux-firmware.
  hardware.enableRedistributableFirmware = true;

  cephClusterNetwork = {
    enable = true;
    interface = "enp4s0f1";
    address = "10.0.70.10";
    rangeStart = "10.0.70.64";
    rangeEnd = "10.0.70.95";
  };

  # enp7s0 is cabled to GS724Tv4 `g18`.
  networking = {
    hostName = "zeus";
    useDHCP = false;

    defaultGateway = {
      address = "10.0.69.1";
      interface = "enp7s0";
    };

    interfaces.enp7s0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.10";
          prefixLength = 24;
        }
      ];
    };
  };

  hardware.facter.detected.dhcp.enable = false;

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    kubernetes-helm
    ldns
  ];

}
