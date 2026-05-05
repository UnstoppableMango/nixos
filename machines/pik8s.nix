idx: {
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
    # raspberry-pi."4".apply-overlays-dtmerge.enable = true;
    # deviceTree = {
    #   enable = true;
    #   filter = "*rpi-4-*.dtb";
    # };
  };

  console.enable = false;

  # environment.systemPackages = with pkgs; [
  #   libraspberrypi
  #   raspberrypi-eeprom
  # ];

  networking = {
    hostName = "pik8s${toString idx}";
    useDHCP = false;

    nameservers = [
      "192.168.1.46"
      "192.168.1.47"
    ];
  };
}
