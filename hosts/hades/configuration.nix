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

  nixpkgs.config.allowUnfree = true;

  imports = [
    ./hardware-configuration.nix
    ./disk-config.nix
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
  #
  # Nope, just makes the problem happen later
  boot.initrd.kernelModules = [ "amdgpu" ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # https://github.com/NixOS/nixpkgs/issues/23926#issuecomment-3298421104
  boot.loader.systemd-boot.configurationLimit = 25;

  networking = {
    hostName = "hades";
    networkmanager.enable = true;
    # Temporary manual host entry while Pi-hole DNS is broken.
    # TODO: Remove this once Pi-hole is healthy and resolving ncps.thecluster.lan correctly.
    hosts = {
      "192.168.1.43" = ["ncps.thecluster.lan"];
    };
  };

  time.timeZone = "America/Chicago";
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

  # For cache fallback behaviour
  nix.package = pkgs.nixVersions.latest;

  programs.zsh.enable = true;
  users.defaultUserShell = pkgs.bash;

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

      ## Maybe eventually
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

      # Broken ATM
      # chiaki-ng

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
      MIIDqTCCA1ugAwIBAgIRAP3DFbRphLU1I5G7SgUWB8cwBQYDK2VwMDsxCzAJBgNV
      BAYTAlVTMRAwDgYDVQQKEwdVbk1hbmdvMRowGAYDVQQDExFVbk1hbmdvIEF1dGhv
      cml0eTAeFw0yNDA3MjIwNTI1NTdaFw00OTA3MTYwNTI1NTdaMFIxCzAJBgNVBAYT
      AlVTMRAwDgYDVQQKEwdVbk1hbmdvMRkwFwYDVQQLExBVbnN0b3BwYWJsZU1hbmdv
      MRYwFAYDVQQDEw10aGVjbHVzdGVyLmlvMIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
      MIICCgKCAgEAxdhA+xxuQYucY2eDgHg5paLEOT6dHGTlULhu5n3HwmGy8PDUSFPR
      hMUwWgurKEZlNdA77I2DP2pBfyT3FqGosbWtke2HFq3zOaap1UCHkd6NuYb7rEwI
      Nlcd3cTw+/U8yUGJsjkaS2VBbbTyuWAcGvguQmpf/r5Su8ilDN/4MFMan6qRCGoB
      yTPB8DfBsqcGUgu94mNaE1onnAisMYERWeED1lnlZKuo+Ff8dp9uS+xM/zFTRtSs
      BYtF/RALUrH964UiXW3vLA0kzfXDc3b6RKTGT0jl5/oLHHSi38sRLdXxogVdZLFm
      XLYm4fuHJRCMHm0/ejM2KvIK9DT05QsqQCw1IMtbZxsLGG7PgoheaDIiXavx0A/c
      yCwG+8WrRJearruHb1JDVAVMufFcHQX+UlUvIXQrjeVSfsPLiVbYLSg/VLjwLPgP
      /EkF14lxLxObkKLOmLbyOHP6KybdATgHJeZVK9BA6awmlQASSKwvrmwkdze7ESkG
      JTh495w3N3qcQ2DidQ2pn59moN43nGTU6cvPgqDR2UZzxUvh10fk45Ayj4LVXdsp
      APKOW1dHkk55VYEI9+MMzjlV+qPlH4Am2R40o/B+KQh1HkpUXz7lsFpkjEraBBia
      qMdDxT2qdbR9nyBR01lcXujcGa/pXqNNV93fVrrPT9VakcngFiqQ1i0CAwEAAaNj
      MGEwDgYDVR0PAQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFJdi
      KvNTkRcWLmJ8vcD2/AmuCOKiMB8GA1UdIwQYMBaAFOYurdBkToYbj1m0tvjcDvQY
      j7dUMAUGAytlcANBALA6/GiSW3js9iarFiqloS+jI9kfqHABufe4XDuiZXL6sB9K
      1bJtYQRzzKLOfQ5/GPf44JIhJPR5k2h4nkZ17gE=
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
