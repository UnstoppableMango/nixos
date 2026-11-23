# The VM disk: a WD SN7100 2 TB on a PCIe M.2 adapter, holding the `vms`
# volume group (#519, docs/nix-ci.md "Hardware").
#
# Each logical volume becomes one microVM's virtio disk, so neither carries a
# filesystem and nothing mounts it on the host. The guest formats its own.
# Sizes are GiB: of the drive's 1863 GiB, about 263 stay unallocated as growth
# and wear headroom.
#
# Its own file so `disko` can format this disk alone without touching the
# booted OS disk.
{
  disko.devices = {
    disk.vms = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_2TB_SERIAL_TODO";
      content = {
        type = "gpt";
        partitions.pv = {
          size = "100%";
          content = {
            type = "lvm_pv";
            vg = "vms";
          };
        };
      };
    };

    lvm_vg.vms = {
      type = "lvm_vg";
      lvs = {
        # The builder microVM's /nix (#529).
        builder.size = "1200G";

        # The attic microVM's storage (#524).
        attic.size = "400G";
      };
    };
  };
}
