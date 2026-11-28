# An NVIDIA GPU for rosequartz pods, through the-cluster's nvidia RuntimeClass.
{ config, lib, ... }:
{
  # nouveau leaves the only VGA device on a black console ("Cannot find any crtc
  # or sizes"). The nvidia module blacklists it too; this survives dropping the GPU.
  boot.blacklistedKernelModules = [ "nouveau" ];

  # Nothing loads the module eagerly without an X server, so it is listed here.
  services.xserver.videoDrivers = [ "nvidia" ];
  boot.kernelModules = [ "nvidia" ];
  hardware.nvidia = {
    # Turing and newer. Older cards need the proprietary module.
    open = lib.mkDefault true;
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
}
