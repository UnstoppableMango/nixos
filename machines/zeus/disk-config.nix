{
  # Only the 480G boot SSD appears here. zeus also carries eight 500G SATA
  # SSDs and six 10T HDDs, every one of them holding a `ceph_bluestore`
  # partition from the previous cluster. disko formats exactly the devices
  # named below, so those disks survive the install untouched and their OSDs
  # stay importable. Do not add them here.
  disko.devices = {
    disk.sda = {
      type = "disk";
      device = "/dev/disk/by-id/ata-SSDSC2KB480G8L_01MP366S7A06680LEN_PHYF83300743480BGN";
      content = {
        type = "gpt";
        partitions = {
          # The box boots in legacy BIOS mode; grub lives here.
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
