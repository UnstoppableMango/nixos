# Kodi on the TV, running under the cage kiosk compositor and always up.
#
# The TV is usually off, so Kodi mostly sits idle on a dark screen. It quits
# itself after 30 idle minutes in its menus and systemd starts it again fresh,
# and a nightly restart covers what that timer skips: Kodi resets it while
# anything is playing or paused, so a video left paused with the TV off would
# otherwise hold its place indefinitely.
{ pkgs, lib, ... }:
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

  # Kodi rewrites guisettings.xml on exit, so the idle timer is set before
  # each start rather than linked from the store the way sources.xml is.
  # A shutdown state of 0 is Quit.
  idleQuit = pkgs.writeShellApplication {
    name = "htpc-kodi-idle-quit";
    runtimeInputs = [ pkgs.xmlstarlet ];
    text = ''
      f=/home/kodi/.kodi/userdata/guisettings.xml
      [ -s "$f" ] || printf '<settings version="2">\n</settings>\n' >"$f"
      xmlstarlet ed -L \
        -d '/settings/setting[@id="powermanagement.shutdowntime" or @id="powermanagement.shutdownstate"]' \
        -s /settings -t elem -n setting -v 30 \
        -i '/settings/setting[last()]' -t attr -n id -v powermanagement.shutdowntime \
        -s /settings -t elem -n setting -v 0 \
        -i '/settings/setting[last()]' -t attr -n id -v powermanagement.shutdownstate \
        "$f"
    '';
  };
in
{
  users.users.kodi = {
    isNormalUser = true;
    # Pinned so the user-1001.slice cap below keeps applying.
    uid = 1001;
    extraGroups = [
      "audio"
      "input"
      "render"
      "video"
    ];
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
      ExecStartPre = "-${lib.getExe idleQuit}";
      # Covers Kodi quitting on its idle timer as well as crashing or being
      # killed at the memory cap.
      Restart = "always";
      RestartSec = 5;
      # cage waits for Kodi on SIGTERM without signalling it, so quit Kodi
      # first. uid 1001 is shared with container users; match the name too.
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
  systemd.slices."user-1001".sliceConfig = {
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
