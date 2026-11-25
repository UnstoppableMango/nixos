# The OS disk, a WD SN850 1 TB. Its own file so `disko` can format it alone.
# Named `os` so its partition labels cannot collide with another NVMe disk's.
{
  disko.devices.disk.os = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-WDS100T1X0E-00AFY0_20496U801727";
    content = {
      type = "gpt";
      partitions = {
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
}
