# Kodi on the TV under cage, always up. It quits after 30 idle minutes in its
# menus and systemd restarts it. Playback resets that timer, so a nightly
# restart covers a video left paused.
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # The copy in Kodi's repository fails to import against urllib3 2.x.
  kodi = pkgs.kodi-wayland.withPackages (p: [
    p.jellyfin
    p.joystick
    p.plex-for-kodi
  ]);

  # Each source's content type lives in Kodi's database, set once from "Set content".
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

  # Kodi rewrites guisettings.xml on exit, so these are set before each start.
  # A shutdown state of 0 is Quit.
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

      # xmlstarlet does not escape &, which would start an entity.
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
    # Pinned, since the slice cap below is named after it. Clear of 1001, the
    # default user of many images. NixOS never changes an existing uid, so a change
    # needs `usermod -u` with Kodi stopped.
    uid = 2000;
    extraGroups = [
      "audio"
      "input"
      "render"
      "video"
    ];
  };

  # For Kore: `clan vars get agreus kodi-webserver/password`.
  clan.core.vars.generators.kodi-webserver = {
    files.password = {
      secret = true;
      owner = "kodi";
    };
    runtimeInputs = [
      pkgs.coreutils
      pkgs.pwgen
    ];
    script = ''
      pwgen -s 32 1 | tr -d '\n' > "$out/password"
    '';
  };

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

  # graphical.target would also start GDM onto the same tty.
  systemd.defaultUnit = lib.mkForce "multi-user.target";
  systemd.services.cage-tty1 = {
    wantedBy = lib.mkForce [ "multi-user.target" ];
    serviceConfig = {
      ExecStartPre = "-${lib.getExe applySettings}";
      Restart = "always";
      RestartSec = 5;
      # cage waits for Kodi on SIGTERM without signalling it. Matching the name keeps
      # container processes sharing the uid out of it.
      ExecStop = "-${pkgs.procps}/bin/pkill -TERM -u kodi -x kodi.bin";
      TimeoutStopSec = 20;
      # Under memory pressure the kernel kills Kodi before any pod.
      OOMScoreAdjust = 500;
    };
  };

  # services.cage leaves restartIfChanged off, so a deploy reaches Kodi only here.
  systemd.services.htpc-kodi-restart = {
    description = "Restart Kodi nightly";
    startAt = "04:00";
    serviceConfig = {
      Type = "oneshot";
      ExecStart = "${pkgs.systemd}/bin/systemctl try-restart cage-tty1.service";
    };
  };

  # Not videolibrary.updateonstartup: Kodi restarts after every idle quit.
  systemd.services.htpc-kodi-scan = {
    description = "Scan Kodi's libraries for new media";
    startAt = "04:10";
    path = with pkgs; [
      coreutils
      curl
    ];
    serviceConfig.Type = "oneshot";
    # On stdin, since other users can read the command line.
    script = ''
      for method in VideoLibrary.Scan AudioLibrary.Scan; do
        printf 'user = "kodi:%s"\n' "$(cat ${webserverPassword})" |
          curl -sSf -K - -H 'Content-Type: application/json' \
            -d "{\"jsonrpc\":\"2.0\",\"method\":\"$method\",\"id\":1}" \
            http://127.0.0.1:8080/jsonrpc
        echo
      done
    '';
  };

  # Capped rather than reserved from the kubelet, so the scheduler counts memory
  # Kodi has not grown into as free.
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

    # HDMI shares a card with the analog jack, and boots onto analog while the TV
    # is off. Preferring HDMI moves the card whenever the TV reports in. No profile
    # is remembered, since that would win over this preference.
    wireplumber.extraConfig."50-htpc-hdmi" = {
      "wireplumber.settings"."device.restore-profile" = false;
      "device.profile.priority.rules" = [
        {
          matches = [ { "device.name" = "~alsa_card.*"; } ];
          actions.update-props.priorities = [ "output:hdmi-stereo" ];
        }
      ];
    };
  };

  environment.systemPackages = [ pkgs.alsa-utils ];

  hardware.bluetooth.enable = true;

  networking.firewall.allowedTCPPorts = [
    8080
    9090
  ];
}
