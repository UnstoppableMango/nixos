{ lib, config, ... }:
{
  options.dotfiles.nvidia.enable = lib.mkEnableOption "NVidia";

  config = lib.mkIf config.dotfiles.nvidia.enable {
    # Open drivers (NVreg_OpenRmEnableUnsupportedGpus=1)
    open = true;

    # nvidia-drm.modeset=1
    modesetting.enable = true;

    # Preserve video memory after suspend
    # NVreg_PreserveVideoMemoryAllocations=1
    powerManagement.enable = true;
  };
}
