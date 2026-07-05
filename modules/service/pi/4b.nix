{ inputs, ... }:
let
  pkgs = inputs.nixpkgs.legacyPackages.aarch64-linux;
in
{
  imports = with inputs; [
    # Not confident about mixing facter + nixos-hardware, but it
    # doesn't seem like facter does any rpi configuration at the moment?
    nixos-hardware.nixosModules.raspberry-pi-4
    ./usb-boot.nix
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
    raspberry-pi."4" = {
      apply-overlays-dtmerge.enable = true;
      poe-hat.enable = true;
    };
  };

  # TODO: make sure everything works before disabling
  # console.enable = false;

  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
  ];

  networking = {
    useDHCP = false;
    nameservers = [
      "192.168.1.46"
      "192.168.1.47"
    ];
  };
}
