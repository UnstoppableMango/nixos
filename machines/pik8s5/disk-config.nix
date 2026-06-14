{ ... }:
{
  # Temporarily disabled for SD card flashing — sda (USB /var drive) requires
  # a second physical device that is not present during initial flash.
  # disko.devices.disk.sda = {
  #   device = "/dev/sda";
  #   type = "disk";
  #   content = {
  #     type = "gpt";
  #     partitions = {
  #       var = {
  #         size = "100%";
  #         content = {
  #           type = "filesystem";
  #           format = "xfs";
  #           extraArgs = [
  #             "-f"
  #             "-L"
  #             "VAR"
  #           ];
  #           mountpoint = "/var";
  #         };
  #       };
  #     };
  #   };
  # };

  # disko.enableConfig = false is set in modules/service/pi/disk-config.nix,
  # so we must declare fileSystems explicitly here too. Use the same lib.mkDefault
  # wrapping pattern so priority matches and the SD card entries in disk-config.nix
  # are not superseded.
  # fileSystems = lib.mkDefault {
  #   "/var" = {
  #     device = "/dev/disk/by-label/VAR";
  #     fsType = "xfs";
  #   };
  # };
}
