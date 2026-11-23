{
  # Only the two NVMe disks appear here. gaea also carries twenty SATA disks
  # between 931G and 12.7T, every one of them holding a `ceph_bluestore`
  # partition from the previous cluster, plus a `tank2` zfs label on one of
  # the 10.9T drives. disko formats exactly the devices named below,
  # so those disks survive the install untouched and their OSDs stay
  # importable. Do not add them here.
  imports = [
    ./disks/os.nix
    ./disks/vms.nix
  ];
}
