{ pkgs, ... }:
{
  imports = [
    ../../modules/ceph
    ../../modules/ceph-cluster-network
    ../../modules/ci-limits
    ../../modules/dns
    ../../modules/nix
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # 32 threads, 125 GB, fifteen OSDs at 4 GiB each.
  ciLimits = {
    memoryMax = 48;
    agentMemoryMax = 8;
    maxJobs = 8;
    cores = 4;
    reservedCpu = 4;
  };

  # Dual Xeon E5-2670 tower whose firmware is in legacy BIOS mode, so it takes
  # grub rather than gaea's systemd-boot. efiSupport keeps the hybrid layout
  # bootable if the firmware ever switches to UEFI.
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

  # enp3s0f0 and enp3s0f1 are the two ports of the SFP+ card, a Broadcom
  # BCM57810. bnx2x loads the card's firmware from linux-firmware when a port
  # comes up, and fails with "Error loading firmware" without it.
  hardware.enableRedistributableFirmware = true;

  # enp3s0f1 is the port cabled to the aggregator.
  cephClusterNetwork = {
    enable = true;
    interface = "enp3s0f1";
    address = "10.0.70.10";
    rangeStart = "10.0.70.64";
    rangeEnd = "10.0.70.95";
  };

  # enp6s0 is the port cabled to GS724Tv4 `g18`. enp7s0, enp11s0, and enp12s0
  # stay unconfigured; two of the board's NICs carried the previous cluster's
  # 10.69.0.0/16 network.
  networking = {
    hostName = "zeus";
    useDHCP = false;

    defaultGateway = {
      address = "10.0.69.1";
      interface = "enp6s0";
    };

    interfaces.enp6s0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.10";
          prefixLength = 24;
        }
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    kubernetes-helm
    ldns
  ];

}
