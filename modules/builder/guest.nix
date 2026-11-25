# The builder VM. /nix lives on the `builder` volume, formatted on first boot:
# the store's writable layer over the system closure, and the Nix database.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.builder;
  net = import ./net.nix;
  attic = import ../attic/net.nix;
  secrets = "/run/builder-secrets";
  agentUnits = map (account: "hercules-ci-agent-${account}.service") cfg.accounts;
  gc = {
    triggerPercent = 15;
    targetPercent = 35;
  };
  # Same request as disk-push, reporting `$success` and `$error`.
  push = endpoint: ''
    printf 'header = "Authorization: Bearer %s"\n' "$(<"$CREDENTIALS_DIRECTORY/token")" |
      curl --config - --fail --silent --show-error --max-time 30 --retry 3 \
      --insecure --pinnedpubkey ${lib.escapeShellArg cfg.gatusPubkey} \
      -G -X POST \
      --data-urlencode "success=$success" \
      --data-urlencode "error=$error" \
      ${lib.escapeShellArg "${cfg.gatusUrl}/api/v1/endpoints/${endpoint}/external"}
  '';
in
{
  options.builder = {
    accounts = lib.mkOption { type = lib.types.listOf lib.types.str; };
    secrets = lib.mkOption {
      type = lib.types.str;
      description = "erofs image of the secrets on the host, attached read-only.";
    };
    atticPubkey = lib.mkOption { type = lib.types.str; };
    gatusUrl = lib.mkOption { type = lib.types.str; };
    gatusPubkey = lib.mkOption { type = lib.types.str; };
  };

  imports = [ ../disk-push ];

  config = {
    system.stateVersion = lib.trivial.release;

    microvm = {
      hypervisor = "cloud-hypervisor";
      vcpu = 32;
      mem = 64 * 1024;
      writableStoreOverlay = "/nix/.rw-store";
      interfaces = [
        {
          type = "tap";
          id = net.tap;
          inherit (net) mac;
        }
      ];
      volumes = [
        {
          image = "/dev/vms/builder";
          serial = "builder";
          direct = true;
          mountPoint = null;
          autoCreate = false;
        }
        {
          image = cfg.secrets;
          serial = "secrets";
          mountPoint = null;
          autoCreate = false;
          readOnly = true;
        }
      ];
    };

    fileSystems."/nix" = {
      device = "/dev/disk/by-id/virtio-builder";
      fsType = "btrfs";
      options = [ "compress=zstd" ];
      autoFormat = true;
      neededForBoot = true;
    };

    fileSystems.${secrets} = {
      device = "/dev/disk/by-id/virtio-secrets";
      fsType = "erofs";
      options = [
        "ro"
        "nodev"
        "nosuid"
        "noexec"
      ];
    };

    networking = {
      useNetworkd = true;
      useDHCP = false;
      enableIPv6 = false;
      # The LAN's resolvers are out of reach.
      nameservers = [
        "9.9.9.9"
        "1.1.1.1"
      ];
    };
    systemd.network.networks."10-tap" = {
      matchConfig.MACAddress = net.mac;
      address = [ "${net.guest}/${toString net.prefixLength}" ];
      routes = [ { Gateway = net.host; } ];
    };

    # The agents hold no roots for running tasks (hercules-ci/hercules-ci-agent#105).
    nix.gc.automatic = false;
    nix.settings = {
      extra-substituters = [
        "http://${attic.guest}:${toString attic.port}/${attic.cache}"
        "https://nix-community.cachix.org"
      ];
      extra-trusted-public-keys = [
        cfg.atticPubkey
        "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      ];
      fallback = true;
      extra-system-features = [ "gccarch-x86-64-v3" ];
      max-jobs = config.microvm.vcpu / 4;
      cores = 4;
      # Off the tmpfs root.
      build-dir = "/nix/var/nix/builds";
    };

    # The database persists but the system closure under the overlay changes
    # with each deploy, so paths it no longer carries are dropped from the
    # database, or fetched again where a valid path refers to them.
    systemd.services.nix-store-verify = {
      description = "Drop or repair store paths the last system closure took along";
      wantedBy = [ "nix-daemon.service" ];
      before = [ "nix-daemon.service" ];
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ config.nix.package ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = "nix-store --verify --repair";
    };

    services.hercules-ci-agents = lib.genAttrs cfg.accounts (account: {
      settings = {
        concurrentTasks = config.microvm.vcpu / 8;
        # Off the tmpfs root.
        baseDirectory = lib.mkForce "/nix/var/lib/hercules-ci-agent-${account}";
        labels = {
          inherit account;
          host = config.networking.hostName;
        };
      };
    });

    # The agent reads its secrets as its own user, which the erofs image cannot
    # name. Only effects on a default branch get the attic token.
    systemd.services.hci-secrets = {
      description = "Install the Hercules CI agents' secrets";
      requiredBy = agentUnits;
      before = agentUnits;
      path = [ pkgs.jq ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        UMask = "0077";
      };
      script = lib.concatMapStrings (
        account:
        let
          inherit (config.services.hercules-ci-agents.${account}) settings;
          user = "hci-${account}";
          install = "install -o ${user} -g ${user} -m 0400";
        in
        ''
          install -d -o ${user} -g ${user} -m 0700 ${settings.staticSecretsDirectory}
          ${install} ${secrets}/${account}-cluster-join-token ${settings.clusterJoinTokenPath}
          ${install} ${secrets}/${account}-binary-caches ${settings.binaryCachesPath}
          jq -n --rawfile token ${secrets}/attic-push-token '{attic: {kind: "Secret", condition: "isDefaultBranch",
            data: {token: $token, endpoint: "http://${attic.guest}:${toString attic.port}/", cache: "${attic.cache}"}}}' \
            > ${settings.secretsJsonPath}
          chown ${user}:${user} ${settings.secretsJsonPath}
        ''
      ) cfg.accounts;
    };

    systemd.services.agents-push = {
      description = "Push the Hercules CI agents' state to Gatus";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [ pkgs.curl ];
      serviceConfig = {
        Type = "oneshot";
        DynamicUser = true;
        LoadCredential = "token:${secrets}/uptime-push-token";
      };
      script = ''
        success=true error=
        # builder-gc stops the agents on purpose and pages for itself.
        if systemctl is-active --quiet builder-gc.service; then
          error="stopped for builder-gc"
        else
          for unit in ${toString agentUnits}; do
            if ! systemctl is-active --quiet "$unit"; then success=false error+=" $unit"; fi
          done
          error="not active:$error"
        fi

        ${push "builder_agents"}
      '';
    };

    systemd.timers.agents-push = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "5min";
        OnUnitActiveSec = "5min";
      };
    };

    # No roots are kept, and running tasks are interrupted rather than drained.
    systemd.services.builder-gc = {
      description = "Collect the store when /nix runs low";
      after = [ "network-online.target" ];
      wants = [ "network-online.target" ];
      path = [
        pkgs.coreutils
        pkgs.curl
        config.nix.package
      ];
      serviceConfig = {
        Type = "oneshot";
        LoadCredential = "token:${secrets}/uptime-push-token";
        ExecStopPost = "${config.systemd.package}/bin/systemctl start --no-block ${lib.escapeShellArgs agentUnits}";
      };
      script = ''
        measure() {
          # btrfs frees extents when the transaction commits.
          sync -f /nix
          read -r size avail < <(df --block-size=1 --output=size,avail /nix | tail -n 1)
        }
        below() { ((avail * 100 < size * $1)); }

        measure
        success=true
        if below ${toString gc.triggerPercent}; then
          systemctl stop ${toString agentUnits}
          deficit() { echo $((size * ${toString gc.targetPercent} / 100 - avail)); }
          max=$(deficit)
          while below ${toString gc.targetPercent}; do
            before=$avail
            nix --extra-experimental-features nix-command store gc --max "$max" || break
            measure
            ((avail > before)) || break
            # --max counts uncompressed bytes, which zstd frees less of.
            max=$(($(deficit) * (max * 100 / (avail - before)) / 100 + 1))
          done
          if below ${toString gc.targetPercent}; then success=false; fi
          error="collected to $((avail * 100 / size))% free, target ${toString gc.targetPercent}%"
        else
          error="$((avail * 100 / size))% free, nothing to collect"
        fi

        ${push "builder_gc"}
      '';
    };

    systemd.timers.builder-gc = {
      wantedBy = [ "timers.target" ];
      timerConfig = {
        OnBootSec = "15min";
        OnUnitActiveSec = "1h";
      };
    };

    diskPush = {
      url = cfg.gatusUrl;
      endpoint = "builder_disk";
      path = "/nix";
      tokenFile = "${secrets}/uptime-push-token";
      pubkeyFile = cfg.gatusPubkey;
    };
  };
}
