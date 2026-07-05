{ lib, ... }:
{
  # SSD layout: firmware + root only. /var lives on root (no separate partition
  # needed since the full OS is on the SSD).
  # Custom labels (USB_BOOT / NIXOS_USB) prevent by-label mount ambiguity when the
  # SD card (labeled FIRMWARE / NIXOS_SD) is present as a fallback device.
  # disko.enableConfig = false: prevents disko from generating conflicting fileSystems.
  # fileSystems are declared here for the runtime deployed system; in the sd-card image
  # sub-evaluation sd-image.nix generates identical entries after the sdImage options
  # in image.modules.sd-card take effect (mergeEqualOption allows same-value dedup).
  disko.enableConfig = false;

  fileSystems = {
    "/boot/firmware" = {
      device = "/dev/disk/by-label/USB_BOOT";
      fsType = "vfat";
      # mkDefault yields to sd-image.nix's [ "nofail" "noauto" ] in image builds;
      # applied as-is for the deployed runtime system.
      options = lib.mkDefault [
        "fmask=0022"
        "dmask=0022"
        "nofail"
      ];
    };
    "/" = {
      device = "/dev/disk/by-label/NIXOS_USB";
      fsType = "ext4";
    };
  };

  # image.modules uses deferredModule — option names are not validated until the
  # sd-card sub-evaluation runs (where sd-image.nix has loaded sdImage options).
  image.modules.sd-card = {
    sdImage.rootVolumeLabel = "NIXOS_USB";
    sdImage.firmwarePartitionName = "USB_BOOT";
    sdImage.firmwareSize = 256;
  };

  disko.devices.disk.sda = {
    device = "/dev/sda";
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
              "USB_BOOT"
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
              "NIXOS_USB"
            ];
            mountpoint = "/";
          };
        };
      };
    };
  };
}
