{ pkgs, ... }:
let
  primaryUser = "erik";
in
{
  nix.settings = {
    # dotfiles' modules/zed sets this only in erik's nix.conf, which the daemon
    # ignores. Keep the key in step with that module.
    extra-substituters = [ "https://zed.cachix.org" ];
    extra-trusted-public-keys = [
      "zed.cachix.org-1:/pHQ6dpMsAZk2DiP4WCL0p9YDNKWj2Q5FL20bNmw1cU="
    ];

    # Marks AVX2 so derivations that need it (nixpkgs' bun) skip zeus (#416).
    system-features = [
      "kvm"
      "gccarch-x86-64-v3"
    ];

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

  # Language servers watching module caches exhaust systemd's 524288 default.
  boot.kernel.sysctl."fs.inotify.max_user_watches" = 1048576;

  networking = {
    hostName = "hades";
    # enp6s0 and enp7s0 share a MAC address, which breaks DHCP, so both wired
    # interfaces are static and NM manages only wlp5s0.
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
    # Resolvers come from ../../modules/dns.
  };

  # A workstation keeps the manual the server defaults drop.
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

  # No ibus: on Wayland it cannot deliver input into bwrap sandboxes, so text
  # fields in apps like Omnissa Horizon Client stop working.
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

      # podman-compose containers need this to reach each other.
      defaultNetwork.settings.dns_enabled = true;
    };
  };

  programs.virt-manager.enable = true;
  users.groups.libvirtd.members = [ primaryUser ];
  users.groups.libvirt.members = [ primaryUser ];
  virtualisation.libvirtd.enable = true;
  virtualisation.spiceUSBRedirection.enable = true;

  services.xserver.enable = true;
  services.xserver.videoDrivers = [ "amdgpu" ];

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

  services.printing.enable = true;

  services.pulseaudio.enable = false;
  security.rtkit.enable = true;
  services.pipewire = {
    enable = true;
    alsa.enable = true;
    alsa.support32Bit = true;
    pulse.enable = true;

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

  host.brave.enable = true;
  host.gnome.enable = true;
  ssh.inhibitSleepOnSsh.enable = true;

  # erik's home is a standalone Home Manager install from the dotfiles repo.
  users.users.${primaryUser} = {
    shell = pkgs.zsh;
    description = "Erik Rasmussen";

    # Lingering keeps claude-remote-control.service up, which can reattach to
    # sessions only for about four hours after the previous server stopped.
    linger = true;

    extraGroups = [
      "openrazer"
      "libvirt" # crc wants `libvirt` not `libvirtd`
      "docker" # /var/run/docker.sock is root-owned; this group is the access path
      "podman"
    ];
  };

  # tz's home is a standalone Home Manager install from the dotfiles repo.
  users.users.tz = {
    packages = [ pkgs.home-manager ];
    shell = pkgs.zsh;
  };

  # 1Password's browser integration, system unlock and setgid `op` need the
  # NixOS modules.
  programs._1password.enable = true;
  programs._1password-gui = {
    enable = true;
    polkitPolicyOwners = [ "tz" ];
  };

  # Shields up refuses inbound tailnet connections, since the firewall is off.
  # `tailscale logout` clears both prefs; tailscaled-set reapplies them on the
  # next `systemctl restart tailscaled`.
  services.tailscale = {
    enable = true;
    extraSetFlags = [
      "--operator=tz"
      "--shields-up"
    ];
  };

  services.displayManager.autoLogin.enable = true;
  services.displayManager.autoLogin.user = primaryUser;
  # GDM otherwise autologs into whichever session was picked last.
  services.displayManager.defaultSession = "gnome";

  # GDM's Xsession wrapper `eval`s Exec, so $HOME expands at login.
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

  # The only Hyprland on the machine: the home config sets its package to null.
  # No uwsm: it conflicts with Home Manager's hyprland-session.target.
  programs.hyprland.enable = true;
  # programs.hyprland does not add hyprlock's PAM service.
  security.pam.services.hyprlock = { };

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


  # The system half of dotfiles' modules/yubikey.
  services.pcscd.enable = true;
  services.udev.packages = [ pkgs.yubikey-personalization ];

  services.lldpd.enable = true;

  # GitHub Copilot CLI's bash tool hardcodes /bin/bash.
  # https://github.com/github/copilot-cli/issues/3392
  services.envfs.enable = true;

  dotfiles.unifi.enable = true;

  networking.firewall.enable = false;

  # The release of the first install. Do not change it.
  system.stateVersion = "25.05";
}
