# Pushes free space on / to the Gatus endpoint `disk_<hostname>`, which
# `uptime.pushes.disk` on pik8s3 must declare.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.diskPush;
  inherit (config.clan.core.vars.generators) uptime-push;
in
{
  imports = [ ../uptime/push-token.nix ];

  options.diskPush = {
    url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "http://10.0.69.103:8080";
      description = "Gatus to push to. Null disables the push.";
    };

    minFreePercent = lib.mkOption {
      type = lib.types.ints.between 0 100;
      default = 10;
      description = "Free space on `/`, in percent, below which a push reports failure.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "Time between pushes. Shorter than the endpoint's heartbeat in Gatus.";
    };
  };

  config = lib.mkIf (cfg.url != null) {
    systemd.services.disk-push = {
      description = "Push free space on / to Gatus";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.coreutils
        pkgs.curl
      ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        LoadCredential = "token:${uptime-push.files.token.path}";
      };
      script = ''
        read -r size avail < <(df --output=size,avail / | tail -n 1)
        free=$((avail * 100 / size))
        success=true
        if ((free < ${toString cfg.minFreePercent})); then success=false; fi

        # -G puts the fields in the query string, where Gatus reads them.
        curl --fail --silent --show-error --max-time 30 --retry 3 \
          -G -X POST \
          -H "Authorization: Bearer $(cat "$CREDENTIALS_DIRECTORY/token")" \
          --data-urlencode "success=$success" \
          --data-urlencode "error=$free% free on /" \
          ${lib.escapeShellArg "${cfg.url}/api/v1/endpoints/disk_${config.networking.hostName}/external"}
      '';
    };

    systemd.timers.disk-push = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "1min";
        OnUnitActiveSec = cfg.interval;
      };
    };
  };
}
