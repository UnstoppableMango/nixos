{ config, pkgs, ... }:

{
  # imports =
  #   [
  #     ./hardware-configuration.nix
  #   ];

  # Enable nix flakes
  nix.package = pkgs.nixVersions.stable;
  nix.extraOptions = ''
    experimental-features = nix-command flakes
  '';

  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking.hostName = "hades";

  time.timeZone = "America/Chicago";

  networking.useDHCP = false;
  networking.interfaces.enp6s0.useDHCP = true;
  networking.interfaces.enp7s0.useDHCP = true;

  # Enable the Plasma 5 Desktop Environment
  services.xserver.enable = true;
  services.xserver.displayManager.sddm.enable = true;
  services.xserver.desktopManager.plasma5.enable = true;

  # Enable CUPS
  # services.printing.enable = true;

  # Enable sound
  sound.enable = true;
  hardware.pulseaudio.enable = true;

  # Enable touchpad support
  # services.xserver.libinput.enable = true;

  users.users.erik = {
    isNormalUser = true;
    extraGroups = [ "wheel" ];
  };
}
