{
  # The CSI plugins modprobe rbd and ceph through the host's /lib/modules,
  # which NixOS leaves absent. The booted system matches `uname -r`.
  systemd.tmpfiles.rules = [
    "L+ /lib/modules - - - - /run/booted-system/kernel-modules/lib/modules"
  ];
}
