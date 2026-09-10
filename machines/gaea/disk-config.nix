{
  # Only the 512G boot NVMe appears here. gaea also carries twenty SATA disks
  # between 931G and 12.7T, every one of them holding a `ceph_bluestore`
  # partition from the previous cluster, plus a `tank2` zfs label on one of
  # the 10.9T drives. disko formats exactly the devices named below,
  # so those disks survive the install untouched and their OSDs stay
  # importable. Do not add them here.
  disko.devices = {
    disk.nvme0n1 = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-WDC_WDS512G1X0C-00ENX0_172459421247";
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
  };
}
