{ pkgs, ... }:
{
  imports = [ ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot = {
      enable = true;
      configurationLimit = 10;
    };
  };

  nixpkgs.hostPlatform = "aarch64-linux";

  hardware = {
    # TODO: Wtf does this all mean
    # raspberry-pi."4".apply-overlays-dtmerge.enable = true;
    # deviceTree = {
    #   enable = true;
    #   filter = "*rpi-4-*.dtb";
    # };
  };

  console.enable = false;

  environment.systemPackages = with pkgs; [
    libraspberrypi
    raspberrypi-eeprom
  ];

  networking = {
    # TODO
    # hostName = "pik8s${instanceName}";
    useDHCP = false;

    nameservers = [
      "192.168.1.46"
      "192.168.1.47"
    ];
  };
}
