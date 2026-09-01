{ inputs, ... }:
let
  pkgs = inputs.nixpkgs.legacyPackages.aarch64-linux;
in
{
  imports = with inputs; [
    # Not confident about mixing facter + nixos-hardware, but it
    # doesn't seem like facter does any rpi configuration at the moment?
    #
    # NOTE: this switches boot.kernelPackages to linux_rpi4 (RPi Foundation's
    # downstream kernel fork), which isn't reliably cached by Hydra the way the
    # default linuxPackages kernel is, so it tends to build from source.
    nixos-hardware.nixosModules.raspberry-pi-4
  ];

  boot = {
    # https://discourse.nixos.org/t/cannot-build-raspberry-pi-sdimage-module-dw-hdmi-not-found/71804/5
    initrd.allowMissingModules = true;
    initrd.availableKernelModules = [
      "xhci_pci"
      "usbhid"
      "usb_storage"
    ];

    loader = {
      grub.enable = false;
      generic-extlinux-compatible.enable = true;
    };

    zfs.forceImportRoot = false;
  };

  nixpkgs.buildPlatform = "aarch64-linux";
  nixpkgs.hostPlatform = "aarch64-linux";

  hardware = {
    raspberry-pi."4".apply-overlays-dtmerge.enable = true;

    # The PoE HAT uses the stock rpi-poe overlay. All of its fan-curve
    # parameters are optional and the defaults are what we want.
    raspberry-pi.configtxt.deviceTreeOverlays."board-type=0x11" = [
      { rpi-poe = { }; }
    ];
  };

  # TODO: make sure everything works before disabling
  # console.enable = false;

  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
  ];

  networking.useDHCP = false;
}
