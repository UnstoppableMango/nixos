{ lib, ... }:
{
  # Disable disko's automatic fileSystems generation so we can set them explicitly using
  # by-label device paths below. disko still uses the disk layout for `clan machines install`
  # / nixos-anywhere; it just won't emit fileSystems entries.
  disko.enableConfig = false;

  disko.devices.disk.mmcblk0 = {
    device = "/dev/mmcblk0";
    type = "disk";
    content = {
      type = "gpt";
      partitions = {
        firmware = {
          size = "256M";
          type = "EF00";
          content = {
            type = "filesystem";
            format = "vfat";
            extraArgs = [
              "-n"
              "FIRMWARE"
            ];
            mountpoint = "/boot/firmware";
            mountOptions = [
              "fmask=0022"
              "dmask=0022"
            ];
          };
        };
        root = {
          size = "100%";
          content = {
            type = "filesystem";
            format = "ext4";
            extraArgs = [
              "-L"
              "NIXOS_SD"
            ];
            mountpoint = "/";
          };
        };
      };
    };
  };

  # Explicitly declare fileSystems using by-label paths matching the labels written above
  # (FIRMWARE, NIXOS_SD) and the same labels sd-image-aarch64 expects. This ensures the
  # nixos-anywhere-installed system and the sd-card image use identical device references.
  # lib.mkDefault lets sd-image's own fileSystems definitions take precedence without conflict.
  fileSystems = lib.mkDefault {
    "/boot/firmware" = {
      device = "/dev/disk/by-label/FIRMWARE";
      fsType = "vfat";
      options = [
        "fmask=0022"
        "dmask=0022"
      ];
    };
    "/" = {
      device = "/dev/disk/by-label/NIXOS_SD";
      fsType = "ext4";
    };
  };
}
