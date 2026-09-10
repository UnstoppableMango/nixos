{
  disko.devices = {
    disk.sda = {
      type = "disk";
      device = "/dev/disk/by-id/ata-Samsung_SSD_860_EVO_250GB_S59WNE0M924985D";
      content = {
        type = "gpt";
        partitions = {
          # grub's BIOS boot partition. Paired with the ESP below so the disk
          # boots whichever mode the firmware is in, the same layout pollux
          # (the twin of this box) uses.
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
