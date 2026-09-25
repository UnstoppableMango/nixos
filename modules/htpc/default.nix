# Kodi on the TV, running under the cage kiosk compositor only while it is in use.
#
# The TV keeps HDMI hotplug asserted through standby, so the connector cannot
# tell when it is on. Its network API can: it stops answering in standby.
# htpc-tv-power starts Kodi when the TV turns on and stops it once the TV has
# been off for about 30 seconds. A game controller connecting also starts it,
# for after Kodi was quit with the TV still on.
{ pkgs, lib, ... }:
let
  kodi = pkgs.kodi-wayland.withPackages (p: [ p.joystick ]);

  # Samsung UN50KU630D on VLAN 1. pfSense must pass agreus to it on 8001.
  tv = "192.168.1.75";

  tvPower = pkgs.writeShellApplication {
    name = "htpc-tv-power";
    runtimeInputs = with pkgs; [
      curl
      systemd
    ];
    text = ''
      on=false
      misses=0
      while true; do
        if curl -sf -m 2 -o /dev/null http://${tv}:8001/api/v2/; then
          misses=0
          if ! $on; then
            on=true
            systemctl start cage-tty1.service
          fi
        elif $on && ((++misses >= 3)); then
          on=false
          systemctl stop cage-tty1.service
        fi
        sleep 10
      done
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

  services.cage = {
    enable = true;
    user = "kodi";
    program = "${kodi}/bin/kodi-standalone";
    extraArguments = [
      "-d"
      "-s"
    ];
  };

  # The cage module starts with graphical.target; here only the triggers above start it.
  systemd.defaultUnit = lib.mkForce "multi-user.target";
  systemd.services.cage-tty1 = {
    wantedBy = lib.mkForce [ ];
    serviceConfig = {
      # cage waits for Kodi on SIGTERM without signalling it, so quit Kodi
      # first. uid 1001 is shared with container users; match the name too.
      ExecStop = "-${pkgs.procps}/bin/pkill -TERM -u kodi -x kodi.bin";
      TimeoutStopSec = 20;
      # Under memory pressure the kernel kills Kodi before any pod.
      OOMScoreAdjust = 500;
    };
  };

  # pam_systemd moves the session into kodi's user slice, so the cap goes there.
  # Capped rather than reserved from the kubelet, so pods keep the memory
  # while Kodi is not running.
  systemd.slices."user-1001".sliceConfig = {
    MemoryMax = "2G";
    CPUWeight = 50;
  };

  systemd.services.htpc-tv-power = {
    description = "Start and stop Kodi with the TV's power";
    wantedBy = [ "multi-user.target" ];
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      ExecStart = lib.getExe tvPower;
      Restart = "always";
    };
  };

  services.udev.extraRules = ''
    ACTION=="add", SUBSYSTEM=="input", KERNEL=="event*", ENV{ID_INPUT_JOYSTICK}=="1", RUN+="${pkgs.systemd}/bin/systemctl --no-block start cage-tty1.service"
  '';

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
