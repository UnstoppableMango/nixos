{ pkgs, ... }:
{
  nix.settings = {
    extra-substituters = [
      "https://unstoppablemango.cachix.org"
    ];
    extra-trusted-public-keys = [
      "unstoppablemango.cachix.org-1:m7uEI6X1Ov8DyFWJQX4WsRFRWFuzRW5c/Xms8ZaP74U="
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  fileSystems = {
    "/".options = [ "compress=zstd" ];
    "/home".options = [ "compress=zstd" ];
    "/nix".options = [
      "compress=zstd"
      "noatime"
    ];
  };

  boot.initrd.kernelModules = [ "amdgpu" ];

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
    ];
    packages = with pkgs; [
      vim
      micro
      gnumake
      dprint
      buf
      (
        with dotnetCorePackages;
        combinePackages [
          sdk_9_0
          sdk_10_0
        ]
      )

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
      spotify
      discord
      tutanota-desktop
      slack
      signal-desktop
      claude-monitor

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

  # hardware.nvidia = {
  #   # Open drivers (NVreg_OpenRmEnableUnsupportedGpus=1)
  #   open = true;

  #   # nvidia-drm.modeset=1
  #   modesetting.enable = true;

  #   # Preserve video memory after suspend
  #   # NVreg_PreserveVideoMemoryAllocations=1
  #   powerManagement.enable = true;
  # };

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
