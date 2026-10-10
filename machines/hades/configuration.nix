{ pkgs, ... }:
let
  primaryUser = "erik";
in
{
  # Shared caches come from ../../modules/cache via the clan-cache instance.
  nix.settings = {
    # dotfiles' modules/zed sets this too, but only in erik's nix.conf, which
    # the daemon does not read. It stays here so `nixos-rebuild` as root also
    # pulls Zed from cache. Keep the key in step with that module.
    extra-substituters = [ "https://zed.cachix.org" ];
    extra-trusted-public-keys = [
      "zed.cachix.org-1:/pHQ6dpMsAZk2DiP4WCL0p9YDNKWj2Q5FL20bNmw1cU="
    ];

    system-features = [ "kvm" ];

    trusted-users = [ primaryUser ];
  };

  nix = {
    # Don't kill my PC when building big things
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    daemonIOSchedPriority = 7;
  };

  nixpkgs.config.allowUnfree = true;

  imports = [
    ./disk-config.nix
    ../../modules/brave
    ../../modules/ci-idle
    ../../modules/desktops
    ../../modules/dns
    ../../modules/nix
    ../../modules/ssh
    ../../modules/unifi
  ];

  fileSystems."/" = {
    device = "/dev/disk/by-uuid/bcc88460-ce1a-455e-9672-4cb20c25b1bf";
    fsType = "btrfs";
    options = [
      "subvol=root"
      "compress=zstd"
    ];
  };

  fileSystems."/nix" = {
    device = "/dev/disk/by-uuid/bcc88460-ce1a-455e-9672-4cb20c25b1bf";
    fsType = "btrfs";
    options = [
      "subvol=nix"
      "compress=zstd"
      "noatime"
    ];
  };

  fileSystems."/home" = {
    device = "/dev/disk/by-uuid/bcc88460-ce1a-455e-9672-4cb20c25b1bf";
    fsType = "btrfs";
    options = [
      "subvol=home"
      "compress=zstd"
    ];
  };

  fileSystems."/boot" = {
    device = "/dev/disk/by-uuid/5CF7-D4A9";
    fsType = "vfat";
    options = [
      "fmask=0022"
      "dmask=0022"
    ];
  };

  fileSystems."/var/lib/docker/btrfs" = {
    device = "/home/root/var/lib/docker/btrfs";
    fsType = "none";
    options = [ "bind" ];
  };

  swapDevices = [ ];

  hardware.openrazer.enable = true;
  hardware.facter.detected.dhcp.enable = false;

  # This continues to randomly stall and fail
  # Removing just makes the problem happen later
  boot.initrd.kernelModules = [
    "dm-snapshot"
    "amdgpu"
  ];

  # Bootloader.
  boot.loader.systemd-boot.enable = true;
  boot.loader.efi.canTouchEfiVariables = true;
  # https://github.com/NixOS/nixpkgs/issues/23926#issuecomment-3298421104
  boot.loader.systemd-boot.configurationLimit = 10;

  boot.kernelModules = [
    "ip6_tables"
    "ip6table_nat"
    "ip_tables"
    "iptable_nat"
  ];

  # Language servers watch entire module caches, so a handful of concurrent
  # editor and agent sessions exhaust systemd's 524288 default.
  boot.kernel.sysctl."fs.inotify.max_user_watches" = 1048576;

  networking = {
    hostName = "hades";
    # enp6s0 (RTL8125 2.5GbE, PCI 06:00.0) and enp7s0 (Intel I211 1GbE, PCI 07:00.0)
    # share the same MAC address. DHCP is unreliable with duplicate MACs so both
    # wired interfaces use static IPs; NM is left to manage wlp5s0.
    networkmanager = {
      enable = true;
      unmanaged = [
        "enp6s0"
        "enp7s0"
      ];
    };
    interfaces = {
      enp6s0.useDHCP = false;
      enp6s0.ipv4.addresses = [
        {
          address = "192.168.1.69";
          prefixLength = 24;
        }
      ];

      enp7s0.useDHCP = false;
      enp7s0.ipv4.addresses = [
        {
          address = "10.0.69.69";
          prefixLength = 24;
        }
      ];
    };
    defaultGateway = {
      address = "192.168.1.1";
      interface = "enp6s0";
    };
    # Resolvers, and the resolvconf ordering that keeps them ahead of the ones
    # NetworkManager picks up from wlp5s0's DHCP lease, come from
    # ../../modules/dns.
  };

  # hades is a workstation, so keep the HTML manual and nixos-help that the
  # recommended defaults drop from servers.
  documentation.doc.enable = true;

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

  # Disable ibus — it intercepts keyboard input on Wayland but can't deliver it
  # back into bwrap sandboxes, making text fields in apps like Omnissa Horizon
  # Client non-interactive. A plain xkb US layout needs no input method daemon.
  i18n.inputMethod = {
    enable = true;
    # type = null; # Disables IBus and other input method frameworks
  };

  virtualisation = {
    containers.enable = true;

    docker = {
      enable = true;
      storageDriver = "btrfs";

      daemon.settings = {
        userland-proxy = false;
      };
    };

    podman = {
      enable = true;

      # Required for containers under podman-compose to be able to talk to each other.
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  # Enable KVM virtualization support
  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = [ primaryUser ];
  users.groups.libvirt.members = [ primaryUser ];
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

  services.earlyoom = {
    enable = true;
    # Kill these last: `.claude-wrapped`, `code`, `code-<commit>`.
    extraArgs = [
      "--avoid"
      "^(\\.?claude|code)"
    ];
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

  boot.binfmt.emulatedSystems = [ "aarch64-linux" ];

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

  ciIdle.activeMemoryHigh = 4;

  host.brave.enable = true;
  host.gnome.enable = true;
  ssh.inhibitSleepOnSsh.enable = true;

  # erik's home environment is a standalone Home Manager install switched with
  # `make home` from the dotfiles repo, not a NixOS module here. This file owns
  # the machine and erik's system account; everything under his home directory,
  # including the rosequartz kubeconfig and its admin identity, is that repo's.
  users.users.${primaryUser} = {
    shell = pkgs.zsh;
    description = "Erik Rasmussen";

    # Start erik's systemd user manager at boot and keep it after logout, so
    # `claude-remote-control.service` is up whenever the machine is. Plain
    # `claude remote-control` reattaches to the sessions the previous server
    # was serving, but only for about four hours after it stopped, and without
    # lingering that clock runs while nobody is logged in.
    linger = true;

    extraGroups = [
      "openrazer"
      "libvirt" # crc wants `libvirt` not `libvirtd`
      "docker" # /var/run/docker.sock is root-owned; this group is the access path
      "podman"
    ];
  };

  # tz's account comes from the `tz` users instance in clan.nix. Like erik's,
  # tz's home is a standalone Home Manager install from the dotfiles repo; this
  # only supplies the CLI to bootstrap it.
  users.users.tz.packages = [ pkgs.home-manager ];

  # Enable automatic login for the user.
  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = primaryUser;
  # GDM otherwise autologs into whichever session was picked last.
  services.displayManager.defaultSession = "gnome";

  # The i3 session from dotfiles' modules/i3, picked from GDM's gear menu.
  # NixOS' GDM Xsession wrapper `eval`s Exec, so $HOME expands at login.
  services.displayManager.sessionPackages = [
    (
      pkgs.writeTextDir "share/xsessions/i3-hm.desktop" ''
        [Desktop Entry]
        Name=i3 (Home Manager)
        Exec=$HOME/.hm-xsession
        Type=Application
        DesktopNames=i3
      ''
      // {
        providedSessions = [ "i3-hm" ];
      }
    )
  ];

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
    libx11
    libxcursor
    libxext
    libxi
    libxrender
    libxtst
    xz
    zlib
  ];

  programs.firefox.enable = false; # Only blue fox
  programs.steam.enable = true;

  # List packages installed in system profile. To search, run:
  # $ nix search wget
  environment.systemPackages = with pkgs; [
    archipelago
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
    kubelogin-oidc
    kind
    yq-go
    ripgrep
    ripgrep-all
    bat
    rsync
    tmux
    ldns
    gnumake
    dprint

    openrazer-daemon
    polychromatic

    gnome-browser-connector
    gnome-shell-extensions
    gnome-settings-daemon
    gnome-tweaks
  ];

  environment.pathsToLink = [ "/share/zsh" ];

  fonts.fontconfig.enable = true;
  fonts.fontDir.enable = true;
  fonts.packages = with pkgs; [
    meslo-lgs-nf
    nerd-fonts.meslo-lg
    nerd-fonts.droid-sans-mono
    nerd-fonts.fira-mono
    nerd-fonts.fira-code
    nerd-fonts.hasklug
    nerd-fonts.jetbrains-mono
    nerd-fonts.meslo-lg
    nerd-fonts.noto
    nerd-fonts.open-dyslexic
    nerd-fonts.roboto-mono

    # Thanks Grey
    open-sans
    corefonts # Microsoft fonts (Arial, Times New Roman, etc.)
    dejavu_fonts # Great standard fallback
    liberation_ttf # Another standard set of fallbacks
    ubuntu-classic
  ];

  # gpg-agent comes from dotfiles' modules/gnupg (signing only). SSH goes
  # through GNOME's gcr-ssh-agent, which dotfiles points SSH_AUTH_SOCK at.

  # The system half of dotfiles' modules/yubikey: scdaemon, ykman, and Yubico
  # Authenticator reach the key through pcscd, and the udev rules grant the
  # logged-in user access to the device.
  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];

  services.lldpd.enable = true;

  # Provide /bin/bash (and other FHS paths) so tools that hardcode /bin/bash work.
  # Workaround for GitHub Copilot CLI's bash tool on NixOS.
  # https://github.com/github/copilot-cli/issues/3392
  services.envfs.enable = true;

  dotfiles.unifi.enable = true;

  # Open ports in the firewall.
  # networking.firewall.allowedTCPPorts = [ ... ];
  # networking.firewall.allowedUDPPorts = [ ... ];
  # Or disable the firewall altogether.
  networking.firewall.enable = false;

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It's perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
