{
  flake.modules.nixos.hardware.nvidia = {
    # Open drivers (NVreg_OpenRmEnableUnsupportedGpus=1)
    open = true;

    # nvidia-drm.modeset=1
    modesetting.enable = true;

    # Preserve video memory after suspend
    # NVreg_PreserveVideoMemoryAllocations=1
    powerManagement.enable = true;
  };
}
