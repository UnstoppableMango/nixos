# Pushes free space on one filesystem to a Gatus external endpoint, which
# `uptime.pushes` on pik8s3 must declare.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.diskPush;
in
{
  options.diskPush = {
    url = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      example = "https://10.0.69.103:8443";
      description = "Gatus to push to. Null disables the push.";
    };

    endpoint = lib.mkOption {
      type = lib.types.str;
      default = "disk_${config.networking.hostName}";
      description = "Gatus endpoint key, `<group>_<name>`.";
    };

    path = lib.mkOption {
      type = lib.types.str;
      default = "/";
      description = "Filesystem whose free space is pushed.";
    };

    minFreePercent = lib.mkOption {
      type = lib.types.ints.between 0 100;
      default = 10;
      description = "Free space on `path`, in percent, below which a push reports failure.";
    };

    interval = lib.mkOption {
      type = lib.types.str;
      default = "5min";
      description = "Time between pushes. Shorter than the endpoint's heartbeat in Gatus.";
    };

    tokenFile = lib.mkOption {
      type = lib.types.str;
      description = "File holding Gatus' push token.";
    };

    pubkeyFile = lib.mkOption {
      type = lib.types.str;
      description = "Gatus' TLS public key, which the push pins.";
    };
  };

  config = lib.mkIf (cfg.url != null) {
    systemd.services.disk-push = {
      description = "Push free space on ${cfg.path} to Gatus";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.coreutils
        pkgs.curl
      ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        LoadCredential = "token:${cfg.tokenFile}";
      };
      script = ''
        read -r size avail < <(df --output=size,avail ${lib.escapeShellArg cfg.path} | tail -n 1)
        free=$((avail * 100 / size))
        success=true
        if ((free < ${toString cfg.minFreePercent})); then success=false; fi

        # -G puts the fields in the query string, where Gatus reads them.
        # The header comes in on stdin, so the token stays out of argv.
        # --insecure skips CA and name checks; the pinned key still
        # authenticates Gatus.
        printf 'header = "Authorization: Bearer %s"\n' "$(<"$CREDENTIALS_DIRECTORY/token")" |
          curl --config - --fail --silent --show-error --max-time 30 --retry 3 \
          --insecure --pinnedpubkey ${lib.escapeShellArg cfg.pubkeyFile} \
          -G -X POST \
          --data-urlencode "success=$success" \
          --data-urlencode "error=$free% free on "${lib.escapeShellArg cfg.path} \
          ${lib.escapeShellArg "${cfg.url}/api/v1/endpoints/${cfg.endpoint}/external"}
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
