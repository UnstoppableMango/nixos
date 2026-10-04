{ inputs, lib, ... }:
let
  # flashrom 1.8.0's cmocka suite fails on aarch64 (write_chip_bad_status_test,
  # plus the leak check), and nixpkgs gates doCheck only on Darwin, so the
  # failure blocks raspberrypi-eeprom and with it system-path. The tests cover
  # flashrom's own chip drivers, not anything rpi-eeprom-update relies on.
  #
  # The override lands here rather than in nixpkgs.overlays because this module
  # takes packages straight from legacyPackages, outside the NixOS pkgs fixpoint
  # an overlay would reach.
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

  # The board modules read the flake from this argument, which
  # nixos-raspberrypi.lib.nixosSystem would otherwise pass in specialArgs.
  _module.args.nixos-raspberrypi = inputs.nixos-raspberrypi;

  # The GPU firmware loads the kernel straight from the firmware partition, so
  # USB SSD boot needs nothing past the EEPROM bootloader. Older generations
  # boot by pointing `os_prefix=` in config.txt at their directory under
  # /boot/firmware/nixos.
  boot.loader.raspberry-pi.bootloader = "kernel";

  boot.zfs.forceImportRoot = false;

  # The Raspberry Pi kernel ships with the memory cgroup controller disabled.
  # Without it runc can't apply memory settings, so no container starts.
  boot.kernelParams = [
    "cgroup_enable=memory"
    "cgroup_memory=1"
  ];

  # The PoE HAT uses the stock rpi-poe overlay. All of its fan-curve parameters
  # are optional and the defaults are what we want.
  hardware.raspberry-pi.config.pi4.dt-overlays.rpi-poe = {
    enable = true;
    params = { };
  };

  # nixos-raspberrypi's sd-image sizes the firmware partition (1024 MiB) for
  # the kernels and initrds the `kernel` bootloader keeps there. Build with
  # `make pik8sN-sd`.
  image.modules.raspberry-pi = {
    imports = [ inputs.nixos-raspberrypi.nixosModules.sd-image ];

    # The sd-image imports nixpkgs' profiles/base.nix, which turns on ZFS and
    # so builds zfs-kernel against the Pi kernel. The installed system has no
    # ZFS, so the image doesn't need it either.
    boot.supportedFilesystems.zfs = lib.mkForce false;
  };

  # TODO: make sure everything works before disabling
  # console.enable = false;

  environment.systemPackages = [ pkgs.raspberrypi-eeprom ];

  networking.useDHCP = false;
}
