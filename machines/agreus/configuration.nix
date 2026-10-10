{ pkgs, lib, ... }:
{
  imports = [
    # home-manager.nixosModules.home-manager
    # dotfiles.nixosModules.erik

    ./disk-config.nix
    ../../modules/ceph
    ../../modules/desktops
    ../../modules/dns
    ../../modules/htpc
    ../../modules/nix
    ../../modules/ssh
    # ../../modules/users/erik
  ];

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot = {
      # A generation costs roughly 37M of kernel plus initrd, so 8 fit in the
      # 500M ESP with room to spare. 25 overflows it and blocks rebuilds, since
      # systemd-boot writes the new entry before pruning the old ones.
      enable = true;
      configurationLimit = 8;
    };
  };

  # Kubelet refuses to start w/ swap on. Disko still makes swapfile on
  # disk, just don't activate it.
  swapDevices = lib.mkForce [ ];

  # https://nixos.wiki/wiki/Power_Management#systemd_sleep
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  networking = {
    hostName = "agreus";
    useDHCP = false;

    defaultGateway = {
      address = "10.0.69.1";
      interface = "enp0s31f6";
    };

    interfaces.enp0s31f6 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.187";
          prefixLength = 24;
        }
      ];
    };
  };

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    kubernetes-helm
    ldns
  ];

  # home-manager.users.erik = {
  #   dotfiles = {
  #     gnome.enable = true;
  #     brave.enable = true;
  #     ghostty.enable = true;
  #     emacs.enable = true;
  #   };
  # };

  # Enable automatic login
  # services.displayManager.autoLogin.enable = true;
  # services.displayManager.autoLogin.user = "office";

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
