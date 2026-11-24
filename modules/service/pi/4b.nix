{ inputs, lib, ... }:
let
  # flashrom 1.8.0's tests fail on aarch64 and block raspberrypi-eeprom; they
  # cover chip drivers rpi-eeprom-update does not use. Not an overlay: this
  # module takes packages from legacyPackages, outside the pkgs fixpoint.
  pkgs = inputs.nixpkgs.legacyPackages.aarch64-linux.extend (
    _: prev: {
      flashrom = prev.flashrom.overrideAttrs { doCheck = false; };
    }
  );
in
{
  imports = [
    inputs.nixos-raspberrypi.lib.int.default-nixos-raspberrypi-config
    inputs.nixos-raspberrypi.nixosModules.raspberry-pi-4.base
  ];

  # nixos-raspberrypi.lib.nixosSystem would otherwise pass this in specialArgs.
  _module.args.nixos-raspberrypi = inputs.nixos-raspberrypi;

  # Older generations boot by pointing `os_prefix=` in config.txt at their
  # directory under /boot/firmware/nixos.
  boot.loader.raspberry-pi.bootloader = "kernel";

  # Adds the `target` and `buildDTBs` attributes our 26.11 NixOS reads and the
  # 26.05 kernel lacks, through `override` so the output path stays the one
  # nixos-raspberrypi.cachix.org serves.
  # TODO: drop once nixos-raspberrypi's main branch moves to 26.11.
  boot.kernelPackages =
    let
      withAttrs =
        kernel:
        kernel
        // {
          target = "Image";
          buildDTBs = true;
          override = f: withAttrs (kernel.override f);
        };
    in
    inputs.nixos-raspberrypi.packages.aarch64-linux.linuxPackages_rpi4.extend (
      _: prev: { kernel = withAttrs prev.kernel; }
    );

  boot.zfs.forceImportRoot = false;

  # Without the memory cgroup, runc can't apply memory settings.
  #
  # The Sabrent enclosures' JMicron JMS578 bridge (152d:a578) drops off the bus
  # under UAS on USB 3, and USB 2 queues etcd's fsyncs behind reads.
  # https://forums.raspberrypi.com/viewtopic.php?f=28&t=245931
  boot.kernelParams = [
    "cgroup_enable=memory"
    "cgroup_memory=1"
    "usb-storage.quirks=152d:a578:u"
  ];

  hardware.raspberry-pi.config.pi4.dt-overlays.rpi-poe = {
    enable = true;
    params = { };
  };

  # Build with `make pik8sN-sd`.
  image.modules.raspberry-pi = {
    imports = [ inputs.nixos-raspberrypi.nixosModules.sd-image ];

    # profiles/base.nix turns on ZFS, which the installed system does not have.
    boot.supportedFilesystems.zfs = lib.mkForce false;
  };

  # TODO: make sure everything works before disabling
  # console.enable = false;

  environment.systemPackages = [ pkgs.raspberrypi-eeprom ];

  networking.useDHCP = false;
}
