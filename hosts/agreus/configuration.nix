{ pkgs, ... }:
{
  nix.settings = {
    extra-substituters = [
      "https://ncps.thecluster.lan"
      "https://nix-community.cachix.org"
      "https://unstoppablemango.cachix.org"
    ];
    extra-trusted-public-keys = [
      "ncps.thecluster.lan:D8fcKW2/D+zjKOABa3bDjEe8x+EPZpXnBDm+XwtNrhI="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "unstoppablemango.cachix.org-1:m7uEI6X1Ov8DyFWJQX4WsRFRWFuzRW5c/Xms8ZaP74U="
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  imports = [
    ./disk-config.nix
  ];

  boot.loader = {
    grub = {
      devices = [ "/dev/nvme0n1" ];
      efiSupport = true;
      efiInstallAsRemovable = true;
    };

    # TODO: Switch to systemd-boot
    # efi.canTouchEfiVariables = true;
    # systemd-boot = {
    #   enable = true;
    #   configurationLimit = 25;
    # };
  };

  # https://nixos.wiki/wiki/Power_Management#systemd_sleep
  systemd.sleep.extraConfig = ''
    AllowSuspend=no
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  networking = {
    hostName = "agreus";
    useDHCP = false;

    networkmanager = {
      enable = true;

      # https://wiki.nixos.org/wiki/NetworkManager#DNS_Management
      insertNameservers = [
        "192.168.1.44"
        "192.168.1.45"
        "1.1.1.1"
        "1.0.0.1"
      ];
    };
  };

  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
  ];

  # https://mynixos.com/nixpkgs/option/users.mutableUsers
  users.mutableUsers = true;
  users.users =
    let
      hadesKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEwW6dUPKvKXXzj+gKJS7EXh6UzyLjzatrcPXa0Y2qvz erik@hades";
      darterKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDB02UwohkEJGpb8Uud4bNQa73X9WvwQcbsRr1M8c7nztbnUCCeLBTyCtRTMnR6dmoQ3xfGLbv55nlTFT/s6ZZKWEAql/gPJoBF9nEr0622IJQ6VPIpgcI8eA2YDwYA0l19Bji4u3VbTMB+M3Tz7JRmKqHo5bUvnZWi2cp+G5Hh2f2k0lQOa9ttjvVlLBQLCJV8NmCxikJS0ZuH2+KJPT2DVsY8dMZ2fQHh1/DI+ZAo6V1qjEU4SQKjpdIrUsPt9Ah1CBU7W3tG57+aYCoaay/BuUY4zlewxGdn3MAv/mjyqF6WgkzCilr7VBnO8CUgzLGu6F+8ljEJVZ5zqyTGfuni/069qMROEp6abhQe7MGToqFgsDkIJhSihomUNylM2piVFobZTeqGBXqh8h3W1fkQHsfMjYbkYP6kHx7yZ03Xw7X+4ZfySZ4s1PqvJE1ZALHdpzYSDK06+iqbJ3ZA/lpipg+Mzx7iRrD3CsPjzgi1iE6w5DVu5xAMIZIRFetTIAs= erik@darter";
    in
    {
      erik = {
        isNormalUser = true;
        home = "/home/erik";
        initialPassword = "Password123!";
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          hadesKey
          darterKey
        ];
      };

      office = {
        isNormalUser = true;
        home = "/home/office";
        initialPassword = "Password123!";
        openssh.authorizedKeys.keys = [
          hadesKey
          darterKey
        ];
      };

      root = {
        openssh.authorizedKeys.keys = [
          hadesKey
        ];
      };
    };

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "office";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
