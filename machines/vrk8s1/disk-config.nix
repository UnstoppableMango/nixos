{
  disko.devices.disk.main = {
    type = "disk";
    # The second 990 PRO (S7KHNJ0WC24447N) is left out, kept blank for later use.
    device = "/dev/disk/by-id/nvme-Samsung_SSD_990_PRO_2TB_S73WNU0XA06456W";
    content = {
      type = "gpt";
      partitions = {
        esp = {
          priority = 1;
          name = "ESP";
          size = "1G";
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
}
