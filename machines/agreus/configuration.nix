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
      # More overflows the 500M ESP: systemd-boot writes a new entry before pruning.
      enable = true;
      configurationLimit = 8;
    };
  };

  # Kubelet refuses to start with swap on. Disko still makes the swapfile.
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


  # The release of the first install. Do not change it.
  system.stateVersion = "25.05";
}
