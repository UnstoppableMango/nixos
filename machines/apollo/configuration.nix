{
  config,
  lib,
  pkgs,
  ...
}:
{
  imports = [
    ../../modules/arc-runner-store
    ../../modules/ceph
    ../../modules/ceph-cluster-network
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  arcRunnerStore.enable = true;

  # No ciLimits or Hercules agents: eight OSD memory requests leave no room for a
  # CI slice. These reservations replace the ones ci-limits supplied.
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

  systemd.services.harmonia.serviceConfig.MemoryMax = "2G";

  # Firmware mode unverified, so castor's dual-mode grub.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # nouveau leaves the only VGA device on a black console ("Cannot find any crtc
  # or sizes"). The nvidia module blacklists it too; this survives dropping the GPU.
  boot.blacklistedKernelModules = [ "nouveau" ];

  # Nothing loads the module eagerly without an X server, so it is listed here.
  services.xserver.videoDrivers = [ "nvidia" ];
  boot.kernelModules = [ "nvidia" ];
  hardware.nvidia = {
    # 590 dropped Pascal. CUDA 13 does not target it either, so pods need CUDA 12.
    branch = "legacy_580";
    open = false;
    # Otherwise every pod start reinitialises the driver.
    nvidiaPersistenced = true;
    nvidiaSettings = false;
  };

  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "nvidia-x11"
      "nvidia-persistenced"
      "nvidia-kernel-modules"
    ];

  # The runtime looks NVIDIA_VISIBLE_DEVICES up as `nvidia.com/gpu=<UUID>`.
  hardware.nvidia-container-toolkit = {
    enable = true;
    device-name-strategy = "uuid";
  };

  # Handler for the-cluster's nvidia RuntimeClass.
  virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri".containerd.runtimes.nvidia =
    {
      runtime_type = "io.containerd.runc.v2";
      options = {
        BinaryName = "${lib.getOutput "tools" config.hardware.nvidia-container-toolkit.package}/bin/nvidia-container-runtime.cdi";
        SystemdCgroup = true;
      };
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
