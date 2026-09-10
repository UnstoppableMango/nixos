{
  # Host-side prerequisites for the rook-ceph CSI node plugins.
  #
  # `csi-rbdplugin` runs `modprobe rbd` at startup inside a container that
  # bind-mounts the host's `/lib/modules`. NixOS keeps kernel modules under the
  # booted system's store path and leaves `/lib/modules` absent, so the mount
  # lands on an empty directory and modprobe fails with
  # "Module rbd not found in directory /lib/modules/<version>", which the plugin
  # treats as fatal. `csi-cephfsplugin` hits the same gap later, when it mounts
  # a volume and the kernel needs the `ceph` module.
  #
  # The symlink points at the booted system rather than the current one so the
  # module tree always matches the running kernel's `uname -r`.
  systemd.tmpfiles.rules = [
    "L+ /lib/modules - - - - /run/booted-system/kernel-modules/lib/modules"
  ];
}
