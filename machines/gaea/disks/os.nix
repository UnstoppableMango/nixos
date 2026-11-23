# The OS disk, a WD SN850 1 TB in the board's M.2 slot.
#
# Its own file so `disko` can format this disk alone. The CLI reads
# `disko.devices` from the file it is given and ignores `imports`.
#
# Named `os` rather than after its kernel name, so its partition labels
# (`disk-os-ESP`, `disk-os-root`) cannot collide with another NVMe disk's
# `disk-nvme0n1-*`.
{
  disko.devices.disk.os = {
    type = "disk";
    device = "/dev/disk/by-id/nvme-WDS100T1X0E-00AFY0_SERIAL_TODO";
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
