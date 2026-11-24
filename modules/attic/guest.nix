# The attic VM. Its state, atticd's database and NARs included, lives on the
# `vms/attic` logical volume, formatted on first boot.
{
  config,
  lib,
  pkgs,
  utils,
  ...
}:
let
  cfg = config.attic;
  net = import ./net.nix;
  settings = config.services.atticd.settings;
  atticadm = "${lib.getExe' pkgs.attic-server "atticadm"} -f ${
    (pkgs.formats.toml { }).generate "atticd.toml" settings
  }";
  secretsDevice = "/dev/disk/by-id/virtio-secrets";
  secretsUnit = [ "attic-secrets.service" ];
in
{
  options.attic = {
    secrets = lib.mkOption {
      type = lib.types.str;
      description = "The tar of secrets on the host, attached read-only.";
    };
    apiEndpoint = lib.mkOption {
      type = lib.types.str;
      description = "URL clients reach atticd at.";
    };
    gatusUrl = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      description = "Gatus the disk status is pushed to.";
    };
    gatusPubkey = lib.mkOption {
      type = lib.types.str;
      description = "Gatus' TLS public key.";
    };
  };

  imports = [ ../disk-push ];

  config = {
    system.stateVersion = lib.trivial.release;

    microvm = {
      hypervisor = "cloud-hypervisor";
      vcpu = 2;
      mem = 2048;
      registerClosure = false;
      interfaces = [
        {
          type = "tap";
          id = net.tap;
          inherit (net) mac;
        }
      ];
      volumes = [
        {
          image = "/dev/vms/attic";
          serial = "attic";
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

    # Mounted in the initrd, so the users activation writes /var/lib/nixos
    # onto the volume rather than under it.
    fileSystems."/var/lib" = {
      device = "/dev/disk/by-id/virtio-attic";
      fsType = "ext4";
      autoFormat = true;
      neededForBoot = true;
    };

    nix.enable = false;
    # kvm-clock follows gaea, and the VM has no route to an NTP server.
    services.timesyncd.enable = false;

    networking = {
      useNetworkd = true;
      useDHCP = false;
      enableIPv6 = false;
      firewall.allowedTCPPorts = [ net.port ];
    };
    systemd.network.networks."10-tap" = {
      matchConfig.MACAddress = net.mac;
      address = [ "${net.guest}/${toString net.prefixLength}" ];
      routes = [ { Gateway = net.host; } ];
    };

    systemd.services.attic-secrets = {
      description = "Unpack the secrets gaea attaches";
      requires = [ "${utils.escapeSystemdPath secretsDevice}.device" ];
      after = [ "${utils.escapeSystemdPath secretsDevice}.device" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        RuntimeDirectory = "attic-secrets";
        RuntimeDirectoryMode = "0700";
        ExecStart = "${lib.getExe pkgs.gnutar} --extract --file ${secretsDevice} --directory /run/attic-secrets";
      };
    };

    users.users.atticd = {
      isSystemUser = true;
      group = "atticd";
    };
    users.groups.atticd = { };

    services.atticd = {
      enable = true;
      environmentFile = "/run/attic-secrets/atticd.env";
      settings = {
        listen = "0.0.0.0:${toString net.port}";
        api-endpoint = cfg.apiEndpoint;
        garbage-collection.default-retention-period = "90 days";
      };
    };
    systemd.services.atticd = {
      requires = secretsUnit;
      after = secretsUnit;
    };

    # Creates the cache, or brings an existing one back in line, with the
    # signing key from gaea. The key never leaves atticd's database here.
    systemd.services.attic-cache = {
      description = "Configure the ${net.cache} cache";
      wantedBy = [ "multi-user.target" ];
      requires = [ "atticd.service" ] ++ secretsUnit;
      after = [ "atticd.service" ] ++ secretsUnit;
      path = [
        pkgs.curl
        pkgs.jq
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = config.services.atticd.environmentFile;
        RuntimeDirectory = "attic-cache";
        UMask = "0077";
      };
      script = ''
        token=$(${atticadm} make-token --sub setup --validity "5 minutes" \
          --pull ${net.cache} --create-cache ${net.cache} --configure-cache ${net.cache})
        header="$RUNTIME_DIRECTORY/header"
        printf 'Authorization: Bearer %s\n' "$token" > "$header"
        api=http://127.0.0.1:${toString net.port}/_api/v1/cache-config/${net.cache}

        status=$(curl --silent --output /dev/null --write-out '%{http_code}' \
          --retry 30 --retry-connrefused --retry-delay 1 -H "@$header" "$api")
        case $status in
          200) method=PATCH ;;
          404) method=POST ;;
          *) echo "cache-config answered $status" >&2; exit 1 ;;
        esac

        # Paths signed by these upstream keys are not pushed.
        jq --null-input --rawfile key /run/attic-secrets/signing-key '{
          keypair: { Keypair: ($key | rtrimstr("\n")) },
          is_public: true,
          store_dir: "/nix/store",
          priority: 41,
          upstream_cache_key_names: [
            "cache.nixos.org-1",
            "nix-community.cachix.org-1"
          ]
        }' | curl --fail-with-body --silent --show-error -X "$method" \
          -H "@$header" -H 'Content-Type: application/json' --data-binary @- "$api"
      '';
    };

    diskPush = {
      url = cfg.gatusUrl;
      endpoint = "attic_disk";
      path = "/var/lib";
      minFreePercent = 15;
      tokenFile = "/run/attic-secrets/uptime-push-token";
      pubkeyFile = cfg.gatusPubkey;
    };
    systemd.services.disk-push = {
      requires = secretsUnit;
      after = secretsUnit;
    };
  };
}
