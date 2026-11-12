# Kodi on the TV, running under the cage kiosk compositor and always up.
#
# The TV is usually off, so Kodi mostly sits idle on a dark screen. It quits
# itself after 30 idle minutes in its menus and systemd starts it again fresh,
# and a nightly restart covers what that timer skips: Kodi resets it while
# anything is playing or paused, so a video left paused with the TV off would
# otherwise hold its place indefinitely.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  kodi = pkgs.kodi-wayland.withPackages (p: [ p.joystick ]);

  # copyparty in the-cluster (apps/media) serves each media claim read-only over WebDAV.
  # The content type Kodi scrapes each source as lives in its database, so it
  # is set once from "Set content" rather than here.
  sources = {
    video = [
      "movies"
      "movies4k"
      "tv"
      "tv4k"
      "anime"
      "youtube"
    ];
    music = [ "music" ];
  };
  source = dir: ''
    <source>
      <name>${dir}</name>
      <path pathversion="1">davs://copyparty.thecluster.lan/${dir}/</path>
      <allowsharing>true</allowsharing>
    </source>
  '';
  sourcesXml = pkgs.writeText "sources.xml" ''
    <sources>
    ${lib.concatMapAttrsStringSep "\n" (
      type: dirs: "<${type}>\n${lib.concatMapStrings source dirs}</${type}>"
    ) sources}
    </sources>
  '';

  # Kodi rewrites guisettings.xml on exit, so these are set before each start
  # rather than linked from the store the way sources.xml is. Kodi quits after
  # 30 idle minutes (a shutdown state of 0 is Quit), and its web server, which
  # the Kore remote uses, always asks for a login.
  settings = {
    "powermanagement.shutdowntime" = "30";
    "powermanagement.shutdownstate" = "0";
    "services.webserver" = "true";
    "services.webserverauthentication" = "true";
    "services.webserverusername" = "kodi";
  };
  webserverPassword = config.clan.core.vars.generators.kodi-webserver.files.password.path;

  applySettings = pkgs.writeShellApplication {
    name = "htpc-kodi-settings";
    runtimeInputs = [ pkgs.xmlstarlet ];
    text = ''
      f=/home/kodi/.kodi/userdata/guisettings.xml
      [ -s "$f" ] || printf '<settings version="2">\n</settings>\n' >"$f"
      set_setting() {
        xmlstarlet ed -L \
          -d "/settings/setting[@id='$1']" \
          -s /settings -t elem -n setting -v "$2" \
          -i '/settings/setting[last()]' -t attr -n id -v "$1" \
          "$f"
      }
      ${lib.concatMapAttrsStringSep "\n" (
        id: value: "set_setting ${lib.escapeShellArg id} ${lib.escapeShellArg value}"
      ) settings}

      # Kodi keeps the password in plain text in guisettings.xml itself.
      # xmlstarlet reads & in a value as the start of an entity, so it is
      # escaped; it escapes everything else itself.
      if [ -r ${webserverPassword} ]; then
        password=$(cat ${webserverPassword})
        set_setting services.webserverpassword "''${password//&/&amp;}"
      fi
    '';
  };
in
{
  users.users.kodi = {
    isNormalUser = true;
    # Pinned, since the slice cap below is named after it. Kept clear of 1001,
    # the default user of many container images (the ARC runners among them),
    # whose processes would otherwise show up as kodi on this host.
    # NixOS never changes an existing user's uid, so changing this means
    # `usermod -u` on the host with Kodi stopped, or the cap stops applying.
    uid = 2000;
    extraGroups = [
      "audio"
      "input"
      "render"
      "video"
    ];
  };

  # Read by applySettings, which runs as kodi. `clan machines update` prompts
  # for it the first time.
  clan.core.vars.generators.kodi-webserver = {
    prompts.password = {
      description = "Password for Kodi's web server on agreus (user kodi), used by the Kore remote";
      type = "hidden";
    };
    files.password = {
      secret = true;
      owner = "kodi";
    };
    script = ''
      cp "$prompts/password" "$out/password"
    '';
  };

  # A symlink into the store, so sources added from Kodi's UI do not persist.
  systemd.tmpfiles.rules = [
    "d /home/kodi/.kodi 0755 kodi users -"
    "d /home/kodi/.kodi/userdata 0755 kodi users -"
    "L+ /home/kodi/.kodi/userdata/sources.xml - - - - ${sourcesXml}"
  ];

  services.cage = {
    enable = true;
    user = "kodi";
    program = "${kodi}/bin/kodi-standalone";
    extraArguments = [
      "-d"
      "-s"
    ];
  };

  # The cage module starts with graphical.target, which would also start GDM
  # from modules/desktops onto the same tty, so the default stays multi-user.
  systemd.defaultUnit = lib.mkForce "multi-user.target";
  systemd.services.cage-tty1 = {
    wantedBy = lib.mkForce [ "multi-user.target" ];
    serviceConfig = {
      # Not fatal, so a malformed guisettings.xml cannot keep Kodi down.
      ExecStartPre = "-${lib.getExe applySettings}";
      # Covers Kodi quitting on its idle timer as well as crashing or being
      # killed at the memory cap.
      Restart = "always";
      RestartSec = 5;
      # cage waits for Kodi on SIGTERM without signalling it, so quit Kodi
      # first. Matching the name as well keeps a container process that
      # happens to share the uid out of it.
      ExecStop = "-${pkgs.procps}/bin/pkill -TERM -u kodi -x kodi.bin";
      TimeoutStopSec = 20;
      # Under memory pressure the kernel kills Kodi before any pod.
      OOMScoreAdjust = 500;
    };
  };

  # Kodi never returns memory it has grown into, and services.cage leaves
  # restartIfChanged off, so a deploy reaches a running Kodi only here.
  systemd.services.htpc-kodi-restart = {
    description = "Restart Kodi nightly";
    startAt = "04:00";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl try-restart cage-tty1.service";
    };
  };

  # pam_systemd moves the session into kodi's user slice, so the cap goes there.
  # Capped rather than reserved from the kubelet, so the scheduler still
  # counts the memory Kodi has not grown into as free for pods.
  systemd.slices."user-${toString config.users.users.kodi.uid}".sliceConfig = {
    MemoryMax = "2G";
    CPUWeight = 50;
  };

  hardware.graphics = {
    enable = true;
    extraPackages = [ pkgs.intel-media-driver ];
  };

  services.pipewire = {
    enable = true;
    alsa.enable = true;
    pulse.enable = true;
  };

  hardware.bluetooth.enable = true;

  # Kodi's web server and JSON-RPC, used by the Kore remote app.
  networking.firewall.allowedTCPPorts = [
    8080
    9090
  ];
}
