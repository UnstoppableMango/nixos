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

  # The GTX 1060 (GP106, Pascal) is the only VGA device, so it carries the
  # local console. nouveau deactivates the firmware framebuffer on load and
  # then fails to find a mode on it ("Cannot find any crtc or sizes"), leaving
  # a black screen where the login prompt should be. The nvidia module below
  # blacklists it too; this stays so dropping the GPU config cannot bring the
  # black screen back.
  boot.blacklistedKernelModules = [ "nouveau" ];

  # The GPU is for pods, through the nvidia RuntimeClass and the
  # nvidia-device-plugin in the-cluster (infrastructure/controllers/nvidia-system).
  #
  # `videoDrivers` is how nixpkgs enables the driver; it does not start an X
  # server. Without one, nothing loads the module eagerly, so it is listed
  # here rather than left to modalias, and nvidia-uvm follows through the
  # module's softdep.
  services.xserver.videoDrivers = [ "nvidia" ];
  boot.kernelModules = [ "nvidia" ];
  hardware.nvidia = {
    # 590 and later dropped Pascal. 580 is NVIDIA's long-term branch for it,
    # supported until August 2028. Its CUDA 13 userspace no longer targets
    # Pascal either, so workloads need a CUDA 12 image.
    branch = "legacy_580";
    # The open kernel modules support Turing and later only.
    open = false;
    # No display server holds the device open, so without this the driver
    # tears down its state whenever the last client exits and every pod start
    # pays for reinitialising it.
    nvidiaPersistenced = true;
    # A GTK settings app, for a machine with no desktop.
    nvidiaSettings = false;
  };

  # The driver is unfree. Allow just it, rather than everything, on a machine
  # that otherwise builds nothing unfree.
  nixpkgs.config.allowUnfreePredicate =
    pkg:
    builtins.elem (lib.getName pkg) [
      "nvidia-x11"
      "nvidia-persistenced"
      "nvidia-kernel-modules"
    ];

  # Writes the CDI spec to /run/cdi on boot, which the `nvidia` handler below
  # reads. The device plugin hands each pod NVIDIA_VISIBLE_DEVICES=<GPU UUID>,
  # and the runtime looks that up as `nvidia.com/gpu=<UUID>`, so the spec has
  # to name devices by UUID rather than the default index.
  hardware.nvidia-container-toolkit = {
    enable = true;
    device-name-strategy = "uuid";
  };

  # Handler for the nvidia RuntimeClass in the-cluster. It is runc behind
  # nvidia-container-runtime in CDI mode, which turns the container's
  # NVIDIA_VISIBLE_DEVICES into the device nodes, driver libraries and
  # nvidia-smi from the spec above. runc itself is found on containerd's PATH.
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
