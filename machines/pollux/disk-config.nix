{
  disko.devices = {
    disk.sda = {
      type = "disk";
      device = "/dev/disk/by-id/ata-CT500MX500SSD1_1908E1EC87CD";
      content = {
        type = "gpt";
        partitions = {
          # The box boots in legacy BIOS mode; grub lives here. The ESP is
          # partitioned anyway so flipping the firmware to UEFI later needs
          # no repartitioning.
          boot = {
            name = "boot";
            size = "1M";
            type = "EF02";
          };
          esp = {
            priority = 1;
            name = "ESP";
            size = "500M";
            type = "EF00";
            content = {
              type = "filesystem";
              format = "vfat";
              mountpoint = "/boot";
              mountOptions = [ "umask=0077" ];
            };
          };

          # No swap; kubelet refuses to start with swap on.
          root = {
            size = "100%";
            content = {
              type = "filesystem";
              format = "ext4";
              mountpoint = "/";
            };
          };
        };
      };
    };
  };
}
