{ pkgs, ... }:
{
  imports = [
    ../../modules/arc-runner-store
    ../../modules/ceph
    ../../modules/ceph-cluster-network
    ../../modules/gpu-worker
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  arcRunnerStore.enable = true;

  # No CI here: eight OSD memory requests leave no room for it.
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

  # Firmware mode unverified, so castor's dual-mode grub.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # 590 dropped Pascal. CUDA 13 does not target it either, so pods need CUDA 12.
  hardware.nvidia = {
    branch = "legacy_580";
    open = false;
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

  # GS724Tv4 g10 must be a VLAN 20 access port for this address.
  systemd.network.networks."10-lan" = {
    matchConfig.MACAddress = "40:b0:76:d7:f6:06";
    address = [ "10.0.69.12/24" ];
    gateway = [ "10.0.69.1" ];
  };

  # A second default route would trip the strict reverse-path filter.
  systemd.network.networks."10-unused" = {
    matchConfig.MACAddress = "40:b0:76:d7:f6:07";
    linkConfig.ActivationPolicy = "down";
  };

  # ixgbe refuses the aggregator's non-Intel SFP+ modules otherwise.
  boot.extraModprobeConfig = "options ixgbe allow_unsupported_sfp=1";

  cephClusterNetwork = {
    enable = true;
    interface = "enp12s0f1";
    address = "10.0.70.12";
    rangeStart = "10.0.70.128";
    rangeEnd = "10.0.70.159";
  };

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    kubernetes-helm
    ldns
  ];
}
