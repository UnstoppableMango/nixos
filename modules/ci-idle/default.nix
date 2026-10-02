# Hercules CI agents on a workstation: unrestricted while the desktop is idle,
# squeezed while someone is using it.
#
# An agent evaluates in-process and the evaluator's heap is never handed back
# to the kernel, so an idle agent keeps the size of its largest evaluation.
# While a graphical session is active and unlocked, `ci-idle` lowers the
# slice's `MemoryHigh`, and the kernel reclaims the excess into zram. Without
# swap that heap could not be reclaimed and the agents would stall instead.
#
# Builds run under nix-daemon, which also serves the desktop user's own
# builds, so the daemon stays outside the slice.
{ config, lib, ... }:
let
  cfg = config.ciIdle;
  gib = 1024 * 1024 * 1024;
in
{
  options.ciIdle.activeMemoryHigh = lib.mkOption {
    type = lib.types.ints.positive;
    description = "`MemoryHigh` of `ci.slice` while the desktop is in use, in GiB.";
  };

  config = {
    zramSwap.enable = true;

    systemd.slices.ci = {
      description = "Hercules CI agents";
      # Weights only apply under contention, so the agents still get every
      # core while the desktop is idle.
      sliceConfig = {
        CPUWeight = 20;
        IOWeight = 20;
      };
    };

    systemd.services.hercules-ci-agent-unmango.serviceConfig.Slice = "ci.slice";
    systemd.services.hercules-ci-agent-unstoppablemango.serviceConfig.Slice = "ci.slice";

    systemd.services.ci-idle = {
      description = "Limit ci.slice memory while the desktop is in use";
      wantedBy = [ "multi-user.target" ];
      after = [ "systemd-logind.service" ];
      path = [ config.systemd.package ];
      serviceConfig.Restart = "always";
      # GNOME reports IdleHint to logind once the screen blanks. A session
      # switched to the background can keep IdleHint=no, so Active, logind's
      # foreground flag, is checked too.
      script = ''
        desktop_active() {
          local session props
          while read -r session _; do
            props=$(loginctl show-session "$session" -p Type -p Active -p IdleHint -p LockedHint) || continue
            case $props in
              *Type=wayland* | *Type=x11*) ;;
              *) continue ;;
            esac
            if [[ $props == *Active=yes* && $props == *IdleHint=no* && $props == *LockedHint=no* ]]; then
              return 0
            fi
          done < <(loginctl list-sessions --no-legend)
          return 1
        }

        while true; do
          if desktop_active; then
            want=${toString (cfg.activeMemoryHigh * gib)}
          else
            want=infinity
          fi
          if [[ $(systemctl show ci.slice -p MemoryHigh --value) != "$want" ]]; then
            systemctl set-property --runtime ci.slice MemoryHigh="$want"
            echo "ci.slice MemoryHigh=$want"
          fi
          sleep 30
        done
      '';
    };
  };
}
