{
  disko.devices = {
    disk.main = {
      type = "disk";
      device = "/dev/disk/by-id/TODO";
      content = {
        type = "gpt";
        partitions = {
          # grub's BIOS boot partition, paired with the ESP below so the disk
          # boots whichever mode the firmware is in.
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
