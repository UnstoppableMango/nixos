{ pkgs, ... }:
{
  imports = [
    ../../modules/arc-runner-store
    ../../modules/ceph
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  arcRunnerStore.enable = true;

  # 32 threads, 32 GiB. No ciLimits, and no Hercules agents in clan.nix.
  #
  # apollo carries eight OSDs, six 14 TB drives plus two NVMe, and an OSD's
  # memory request is what the scheduler reserves. Eight of them need more than
  # this host has, so the CI slice cannot also hold 12 GiB. ci-limits reserved
  # memoryMax + 4 as systemReserved plus 2 kubeReserved, which left 11.2 GiB of
  # the 31.2 GiB allocatable and no room for a third OSD.
  #
  # gaea and zeus absorb both roles at 504 GiB and 126 GiB. apollo does not, so
  # it is a storage host only.
  #
  # The reservations below replace the ones ci-limits supplied. Dropping them
  # entirely would hand the scheduler every byte and leave the OSDs to contend
  # with the kernel, which is what ci-limits existed to prevent.
  services.kubernetes.kubelet.extraConfig = {
    systemReserved = {
      cpu = "2";
      memory = "2Gi";
    };
    kubeReserved = {
      cpu = "1";
      memory = "1Gi";
    };
    evictionHard."memory.available" = "1Gi";
  };

  # harmonia took its ceiling from ci.slice, which no longer exists here. It
  # serves this machine's store to the clan and is not a build.
  systemd.services.harmonia.serviceConfig.MemoryMax = "2G";

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

  # Matched by MAC rather than interface name. GS724Tv4 g10 must be a VLAN 20
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
    kubernetes-helm
    ldns
  ];
}
