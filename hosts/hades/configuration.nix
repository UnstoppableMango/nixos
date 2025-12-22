{ pkgs, ... }:
{
  nix.settings = {
    extra-substituters = [
      "https://ncps.thecluster.lan"
      "https://nix-community.cachix.org"
      "https://unstoppablemango.cachix.org"
      "https://zed.cachix.org"
      "https://cache.garnix.io"
    ];
    extra-trusted-public-keys = [
      "ncps.thecluster.lan:D8fcKW2/D+zjKOABa3bDjEe8x+EPZpXnBDm+XwtNrhI="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "unstoppablemango.cachix.org-1:m7uEI6X1Ov8DyFWJQX4WsRFRWFuzRW5c/Xms8ZaP74U="
      "zed.cachix.org-1:/pHQ6dpMsAZk2DiP4WCL0p9YDNKWj2Q5FL20bNmw1cU="
      "cache.garnix.io:CTFPyKSLcx5RMJKfLo5EEPUObbA78b0YQ2DTCJXqr9g="
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  imports = [
    ./hardware-configuration.nix
    ./disko-config.nix
  ];

  fileSystems = {
    "/".options = [ "compress=zstd" ];
    "/home".options = [ "compress=zstd" ];
    "/nix".options = [
      "compress=zstd"
      "noatime"
    ];
  };

  # This continues to randomly stall and fail
  # Going to see if disabling it helps
  # boot.initrd.kernelModules = [ "amdgpu" ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;

  networking = {
    hostName = "hades";
    # wireless.enable = true;  # Enables wireless support via wpa_supplicant.
    networkmanager.enable = true;
  };

  # Set your time zone.
  time.timeZone = "America/Chicago";

  # Select internationalisation properties.
  i18n.defaultLocale = "en_US.UTF-8";

  i18n.extraLocaleSettings = {
    LC_ADDRESS = "en_US.UTF-8";
    LC_IDENTIFICATION = "en_US.UTF-8";
    LC_MEASUREMENT = "en_US.UTF-8";
    LC_MONETARY = "en_US.UTF-8";
    LC_NAME = "en_US.UTF-8";
    LC_NUMERIC = "en_US.UTF-8";
    LC_PAPER = "en_US.UTF-8";
    LC_TELEPHONE = "en_US.UTF-8";
    LC_TIME = "en_US.UTF-8";
  };

  virtualisation.docker = {
    enable = true;
    storageDriver = "btrfs";

    daemon.settings = {
      userland-proxy = false;
    };

    rootless = {
      enable = true;
      setSocketVariable = true;
    };
  };

  # Enable KVM virtualization support
  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = [ "erik" ];
  users.groups.libvirt.members = [ "erik" ];
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  # Enable the X11 windowing system.
  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

  # Enable the GNOME Desktop Environment.
  services.displayManager.gdm.enable = true;
  services.desktopManager.gnome.enable = true;

  environment.gnome.excludePackages = (
    with pkgs;
    [
      atomix # puzzle game
      cheese # webcam tool
      epiphany # web browser
      evince # document viewer
      geary # email reader
      gedit # text editor
      gnome-characters
      gnome-music
      gnome-photos
      gnome-terminal
      gnome-tour
      hitori # sudoku game
      iagno # go game
      tali # poker game
      totem # video player
    ]
  );

  # Configure keymap in X11
  services.xserver.xkb = {
    layout = "us";
    variant = "";
  };

  # Enable CUPS to print documents.
  services.printing.enable = true;

  # Enable sound with pipewire.
  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;
    # If you want to use JACK applications, uncomment this
    #jack.enable = true;

    # use the example session manager (no others are packaged yet so this is enabled by default,
    # no need to redefine it in your config for now)
    #media-session.enable = true;
  };

  services.btrfs.autoScrub = {
    enable = true;
    interval = "weekly";
    fileSystems = [ "/" ];
  };

  programs.appimage = {
    enable = true;
    binfmt = true;
  };

  programs.direnv = {
    enable = true;
    nix-direnv.enable = true;
  };

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.bash;

  # Define a user account. Don't forget to set a password with ‘passwd’.
  users.users.erik = {
    isNormalUser = true;
    shell = pkgs.zsh;
    description = "Erik Rasmussen";
    extraGroups = [
      "networkmanager"
      "wheel"
      "openrazer"
      "libvirt" # crc wants `libvirt` not `libvirtd`
    ];
    packages = with pkgs; [
      vim
      micro
      gnumake
      dprint
      buf

      # Lofty goals lie below
      # jetbrains.webstorm
      # jetbrains.rust-rover
      # jetbrains.ruby-mine
      # jetbrains.rider
      # (pkgs.jetbrains.plugins.addPlugins pkgs.jetbrains.rider ["github-copilot"])
      # jetbrains.idea-ultimate
      # jetbrains.pycharm-professional
      # jetbrains.goland
      # jetbrains.datagrip
      # jetbrains.clion
      jetbrains-toolbox

      gitkraken
      bitwarden-desktop
      bitwarden-cli
      cachix
      chiaki-ng
      spotify
      discord
      tutanota-desktop
      slack
      signal-desktop
      claude-monitor
      omnissa-horizon-client

      (wineWowPackages.full.override {
        wineRelease = "staging";
        mingwSupport = true;
      })
      winetricks
    ];
  };

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = "erik";

  # Workaround for GNOME autologin: https://github.com/NixOS/nixpkgs/issues/103746#issuecomment-945091229
  systemd.services."getty@tty1".enable = false;
  systemd.services."autovt@tty1".enable = false;

  # https://github.com/NixOS/nixpkgs/issues/240444#issuecomment-1977617644
  programs.nix-ld.enable = true;
  programs.nix-ld.libraries = with pkgs; [
    curl
    expat
    fontconfig
    freetype
    fuse
    fuse3
    glib
    icu
    libclang.lib
    libdbusmenu
    libxcrypt-legacy
    libxml2
    nss
    openssl
    python3
    stdenv.cc.cc
    xorg.libX11
    xorg.libXcursor
    xorg.libXext
    xorg.libXi
    xorg.libXrender
    xorg.libXtst
    xz
    zlib
  ];

  programs.firefox.enable = false; # Only blue fox
  programs.steam.enable = true;

  nixpkgs.config.allowUnfree = true;

  hardware.openrazer.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    gcc
    clang
    libllvm
    llvmPackages_20.libllvm
    llvmPackages_19.libllvm
    cmake
    ninja
    python3
    rustup
    rbenv
    git
    nano
    micro
    curl
    jq
    kubectl
    kind
    yq-go
    ripgrep
    ripgrep-all
    bat
    rsync
    tmux
    ldns

    jetbrains-mono
    openrazer-daemon
    polychromatic

    # I'll pick one eventually...
    kdePackages.breeze
    kdePackages.breeze-icons
    paper-icon-theme
    vimix-icon-theme
    papirus-icon-theme

    gnome-browser-connector
    gnome-shell-extensions
    gnome-settings-daemon
    gnome-tweaks
    gimp3

    firefox-devedition
    google-chrome
    vlc
  ];

  environment.pathsToLink = [ "/share/zsh" ];

  fonts.packages = with pkgs; [
    meslo-lgs-nf
    nerd-fonts.droid-sans-mono
    nerd-fonts.fira-mono
    nerd-fonts.fira-code
    nerd-fonts.hasklug
    nerd-fonts.jetbrains-mono
    nerd-fonts.meslo-lg
    nerd-fonts.noto
    nerd-fonts.open-dyslexic
    nerd-fonts.roboto-mono
  ];

  # Some programs need SUID wrappers, can be configured further or are
  # started in user sessions.
  # programs.mtr.enable = true;
  programs.gnupg.agent = {
    enable = true;
    enableSSHSupport = true;
  };

  services.openssh.enable = true;

  security.pki.certificates = [
    # thecluster.lan Nginx CA
    ''
      -----BEGIN CERTIFICATE-----
      MIIDQjCCAiqgAwIBAgIQewg0tCvOBeo2QhAy4f0HAzANBgkqhkiG9w0BAQsFADA7
      MRYwFAYDVQQKEw1pbmdyZXNzLW5naW54MSEwHwYDVQQDExhjYS53ZWJob29rLmlu
      Z3Jlc3MtbmdpbngwHhcNMjUwOTA2MjI0ODEwWhcNMzAwOTA1MjI0ODEwWjA7MRYw
      FAYDVQQKEw1pbmdyZXNzLW5naW54MSEwHwYDVQQDExhjYS53ZWJob29rLmluZ3Jl
      c3MtbmdpbngwggEiMA0GCSqGSIb3DQEBAQUAA4IBDwAwggEKAoIBAQD7C/OMWFln
      g6L2CpvqL7UbN1l5h1ObV9UoMBUFmzdu47bwWrb3lAPlclprW746Mhn0POGn8cM/
      bYnRAdK7nwkEHeTe4uqGIs1wygZTCwhu5Ws272C4Sk/ugbjx+PpPUltR8CV0M6pU
      2aJtZOWfS/X2X42ygY/z1Y9CnJO5gHV2mfWWzcg9Q3w8qAf1nVTNsULxHrHI3vFR
      hxfekBWIoTOORLbIcbYQTIGPHXI+Gm5wDDF6MVE3Kt7oYXslvO+3mePs0zjVivvl
      b2JnuAOM/GubxUt+ab7LhjWk6H3OQvhmkf28M4zWXPWGhfFz39B9ulEznmx/nAhU
      0gWUUO28VIx3AgMBAAGjQjBAMA4GA1UdDwEB/wQEAwICpDAPBgNVHRMBAf8EBTAD
      AQH/MB0GA1UdDgQWBBQNYxQ09OfqkbAJspyZAi4dIriAkzANBgkqhkiG9w0BAQsF
      AAOCAQEAXqmHSRvsrrkkrzSKpZbDAWyVVoibdej274n2zfU1npBbXdhQjx0OeQli
      QE46eN6Ot7WgU/GNJY3J1JZOkP0HKOxtuWPcmT5of9QLzd67t1wm6JHn9D45A62U
      DkBLQgq1rT5Coho+S7bMUlxxJ0odkGrgr8hePKpJcMCdzJGw3+4xP7bzw/vD1a3b
      CraYackx1ugA+rD+sMyNRo5O4stWRug1Hdo9j/AZLAdt5lCpFlhLiWaIwrjdDNxL
      0Laeu9Yx0mNK4os8yVAh106jQF+/in1jqiLE3KJl6RLhzYs2WLgCwOaosE752cPX
      ZY63p/X0MjSTCkswRIco5k1XzgEHrA==
      -----END CERTIFICATE-----
    ''
  ];

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
