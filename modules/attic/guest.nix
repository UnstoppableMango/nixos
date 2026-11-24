# The attic VM. Its state, atticd's database and NARs included, lives on the
# `attic` volume, formatted on first boot.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.attic;
  net = import ./net.nix;
  secrets = "/run/attic-secrets";

  atticdConfig = (pkgs.formats.toml { }).generate "atticd.toml" config.services.atticd.settings;
  atticadm = "${lib.getExe' pkgs.attic-server "atticadm"} -f ${atticdConfig}";

  # Paths signed by the upstream keys are not pushed.
  cacheConfig = (pkgs.formats.json { }).generate "cache-config.json" {
    is_public = true;
    store_dir = "/nix/store";
    priority = 41;
    upstream_cache_key_names = [
      "cache.nixos.org-1"
      "nix-community.cachix.org-1"
    ];
  };
in
{
  options.attic = {
    secrets = lib.mkOption {
      type = lib.types.str;
      description = "erofs image of the secrets on the host, attached read-only.";
    };
    apiEndpoint = lib.mkOption {
      type = lib.types.str;
      description = "URL clients reach atticd at.";
    };
    gatusUrl = lib.mkOption {
      type = lib.types.str;
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

    nix.enable = false;
    # kvm-clock follows the host, and the VM has no route to an NTP server.
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

    users.users.atticd = {
      isSystemUser = true;
      group = "atticd";
    };
    users.groups.atticd = { };

    services.atticd = {
      enable = true;
      environmentFile = "${secrets}/atticd-env";
      settings = {
        listen = "0.0.0.0:${toString net.port}";
        api-endpoint = cfg.apiEndpoint;
        garbage-collection.default-retention-period = "90 days";
      };
    };

    # Creates the cache, or brings it back in line, with the key from the
    # host: the attic CLI cannot import one.
    systemd.services.attic-cache = {
      description = "Configure the ${net.cache} cache";
      wantedBy = [ "multi-user.target" ];
      requires = [ "atticd.service" ];
      after = [ "atticd.service" ];
      path = [
        pkgs.curl
        pkgs.jq
      ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
        EnvironmentFile = config.services.atticd.environmentFile;
        LoadCredential = "signing-key:${secrets}/attic-signing-key";
        RuntimeDirectory = "attic-cache";
        UMask = "0077";
      };
      script = ''
        token=$(${atticadm} make-token --sub setup --validity "5 minutes" \
          --pull ${net.cache} --create-cache ${net.cache} --configure-cache ${net.cache})
        body="$RUNTIME_DIRECTORY/body"
        jq --rawfile key "$CREDENTIALS_DIRECTORY/signing-key" \
          '.keypair.Keypair = ($key | rtrimstr("\n"))' ${cacheConfig} > "$body"

        configure() {
          printf 'header = "Authorization: Bearer %s"\n' "$token" |
            curl --config - --silent --show-error --output /dev/null --write-out '%{http_code}' \
            --retry 30 --retry-connrefused --retry-delay 1 -X "$1" \
            -H 'Content-Type: application/json' --data-binary "@$body" \
            http://127.0.0.1:${toString net.port}/_api/v1/cache-config/${net.cache}
        }
        status=$(configure PATCH)
        if [[ $status == 404 ]]; then status=$(configure POST); fi
        if [[ $status != 200 ]]; then
          echo "cache-config answered $status" >&2
          exit 1
        fi
      '';
    };

    diskPush = {
      url = cfg.gatusUrl;
      endpoint = "attic_disk";
      path = "/var/lib";
      minFreePercent = 15;
      tokenFile = "${secrets}/uptime-push-token";
      pubkeyFile = cfg.gatusPubkey;
    };
  };
}
