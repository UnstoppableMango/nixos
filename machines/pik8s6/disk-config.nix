{ ... }:
{
  # SSD layout: firmware + root only. /var lives on root (no separate partition
  # needed since the full OS is on the SSD).
  # Labels differ from the SD card (FIRMWARE→USB_BOOT, NIXOS_SD→NIXOS_USB) to
  # prevent by-label conflicts when the SD card is present as a fallback device.
  # The Pi EEPROM ignores FAT32 partition labels — it finds firmware files by content.
  disko.enableConfig = false;

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
            format = "xfs";
            extraArgs = [
              "-f"
              "-L"
              "NIXOS_USB"
            ];
            mountpoint = "/";
          };
        };
      };
    };
  };

  fileSystems = {
    "/boot/firmware" = {
      device = "/dev/disk/by-label/USB_BOOT";
      fsType = "vfat";
      options = [
        "fmask=0022"
        "dmask=0022"
        "nofail"
      ];
    };
    "/" = {
      device = "/dev/disk/by-label/NIXOS_USB";
      fsType = "xfs";
    };
  };
}
