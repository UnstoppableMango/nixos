# The VM disk, a WD SN7100 2 TB (#519). Each LV is a microVM's virtio disk,
# formatted by the guest. Sizes are GiB, leaving about 263 GiB free.
{
  disko.devices = {
    disk.vms = {
      type = "disk";
      device = "/dev/disk/by-id/nvme-WD_BLACK_SN7100_2TB_252750801658";
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
