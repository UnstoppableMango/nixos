# A full-screen web page on the attached display: Firefox in kiosk mode under
# the cage compositor, started at boot and restarted if it exits.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.kiosk;
  uid = 1010;

  browser = pkgs.writeShellScript "kiosk-browser" ''
    exec ${lib.getExe config.programs.firefox.package} --kiosk ${lib.escapeShellArg cfg.url}
  '';
in
{
  options.kiosk = {
    enable = lib.mkEnableOption "a web page kiosk on the attached display";

    url = lib.mkOption {
      type = lib.types.str;
      example = "https://thecluster.lan";
      description = "Page the kiosk shows.";
    };

    memoryMax = lib.mkOption {
      type = lib.types.str;
      default = "768M";
      description = ''
        MemoryMax for the kiosk user's slice. On a Kubernetes node, reserve at
        least this much from the kubelet so pods cannot be scheduled into it.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    users.users.kiosk = {
      isNormalUser = true;
      # Pinned so the slice cap below keeps applying.
      inherit uid;
      extraGroups = [
        "input"
        "render"
        "video"
      ];
    };

    services.cage = {
      enable = true;
      user = "kiosk";
      program = browser;
    };

    # Under memory pressure the kernel kills the kiosk before any pod.
    systemd.services.cage-tty1.serviceConfig.OOMScoreAdjust = 500;

    # pam_systemd moves the session into the kiosk user's slice, so the cap goes there.
    systemd.slices."user-${toString uid}".sliceConfig = {
      MemoryMax = cfg.memoryMax;
      CPUWeight = 50;
    };

    programs.firefox = {
      enable = true;
      policies = {
        # Firefox keeps its own certificate store. p11-kit's trust module
        # reads the system bundle, so CAs from security.pki apply here too.
        SecurityDevices.p11-kit-trust = "${pkgs.p11-kit}/lib/pkcs11/p11-kit-trust.so";
        OverrideFirstRunPage = "";
        OverridePostUpdatePage = "";
        DontCheckDefaultBrowser = true;
        DisableTelemetry = true;
        UserMessaging = {
          ExtensionRecommendations = false;
          FeatureRecommendations = false;
          SkipOnboarding = true;
          MoreFromMozilla = false;
        };
      };
    };

    hardware.graphics.enable = true;

    fonts = {
      fontconfig.enable = lib.mkForce true;
      packages = [ pkgs.dejavu_fonts ];
    };
  };
}
