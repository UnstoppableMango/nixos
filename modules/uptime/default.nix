# Gatus outside rosequartz, since nothing inside the cluster can report it down.
# nginx fronts Gatus so pushes, which carry the shared token, arrive only over TLS.
# Pages go to ntfy.sh (`clan vars get pik8s3 uptime-ntfy/topic`). Anyone who
# knows the topic can read it, so alert text must never carry a secret.
{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.uptime;
  inherit (config.clan.core.vars.generators)
    uptime-ntfy
    uptime-push
    uptime-tls
    uptime-tls-key
    ;

  gatusPort = 8079;
  gatus = "http://127.0.0.1:${toString gatusPort}";

  ntfyAlerts = extra: [ ({ type = "ntfy"; } // extra) ];

  tcp = group: name: address: {
    inherit name group;
    url = "tcp://${address}";
    interval = "30s";
    conditions = [ "[CONNECTED] == true" ];
  };

  dns = name: address: {
    inherit name;
    group = "dns";
    url = address;
    interval = "30s";
    dns = {
      # A thecluster.lan name, so a resolver that lost the zone fails too.
      query-name = "ncps.thecluster.lan";
      query-type = "A";
    };
    # NOERROR alone also passes an empty answer, so require an address.
    conditions = [
      "[DNS_RCODE] == NOERROR"
      "[BODY] == pat(*.*.*.*)"
    ];
  };
in
{
  imports = [ ./push-vars.nix ];

  options.uptime = {
    enable = lib.mkEnableOption "the Gatus uptime checker";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port the status page is served on.";
    };

    pushPort = lib.mkOption {
      type = lib.types.port;
      default = 8443;
      description = "Port pushes to external endpoints are accepted on, over TLS.";
    };

    hosts = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        zeus = "10.0.69.10";
      };
      description = "Machines to ping, by name, each an IPv4 address.";
    };

    resolvers = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      example = {
        pik8s1 = "10.0.69.101";
      };
      description = "DNS servers to query for a thecluster.lan name, by name.";
    };

    apiservers = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "kube-apiservers to reach on 6443, by name, each an address.";
    };

    etcd = lib.mkOption {
      type = lib.types.attrsOf lib.types.str;
      default = { };
      description = "etcd members to reach on 2379, by name, each an address.";
    };

    vip = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The apiserver VIP, checked on 6443.";
    };

    gateway = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "The cluster's ingress gateway, checked on 443.";
    };

    services = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.submodule {
          options = {
            url = lib.mkOption {
              type = lib.types.str;
              description = "URL to request.";
            };
            conditions = lib.mkOption {
              type = lib.types.listOf lib.types.str;
              default = [ "[STATUS] == 200" ];
              description = "Gatus conditions the response must meet.";
            };
            page = lib.mkOption {
              type = lib.types.bool;
              default = false;
              description = "Whether a failing check pages through ntfy.";
            };
          };
        }
      );
      default = { };
      example = {
        nextcloud.url = "https://cloud.thecluster.io/status.php";
      };
      description = "Services to check over HTTP, by name.";
    };

    pushes = lib.mkOption {
      type = lib.types.attrsOf (
        lib.types.attrsOf (
          lib.types.submodule {
            options.heartbeat = lib.mkOption {
              type = lib.types.nullOr lib.types.str;
              default = "10m";
              description = ''
                Longest gap between pushes before Gatus records a failure.
                Null accepts pushes without expecting them.
              '';
            };
          }
        )
      );
      default = { };
      example = {
        disk.zeus = { };
      };
      description = ''
        External endpoints that accept pushes, by group and then name. One is
        pushed to at `/api/v1/endpoints/<group>_<name>/external`. A push
        reporting failure pages, as does a missed heartbeat.
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    clan.core.vars.generators.uptime-ntfy = {
      files.topic.deploy = false;
      files.env.secret = true;
      runtimeInputs = [ pkgs.openssl ];
      script = ''
        openssl rand -hex 24 | tr -d '\n' > "$out/topic"
        printf 'GATUS_NTFY_TOPIC=%s\n' "$(cat "$out/topic")" > "$out/env"
      '';
    };

    clan.core.vars.generators.uptime-tls-key = {
      dependencies = [ "uptime-tls" ];
      files.key.owner = "nginx";
      script = ''
        cp "$in/uptime-tls/key" "$out/key"
      '';
    };

    services.nginx = {
      enable = true;
      recommendedProxySettings = true;
      virtualHosts.uptime = {
        default = true;
        listen = [
          {
            addr = "0.0.0.0";
            inherit (cfg) port;
          }
        ];
        locations."/".proxyPass = gatus;
        locations."~ ^/api/v1/endpoints/[^/]+/external$".return = "403";
      };
      virtualHosts.uptime-push = {
        onlySSL = true;
        listen = [
          {
            addr = "0.0.0.0";
            port = cfg.pushPort;
            ssl = true;
          }
        ];
        sslCertificate = uptime-tls.files.cert.path;
        sslCertificateKey = uptime-tls-key.files.key.path;
        locations."~ ^/api/v1/endpoints/[^/]+/external$".proxyPass = gatus;
        locations."/".return = "404";
      };
    };

    networking.firewall.allowedTCPPorts = [
      cfg.port
      cfg.pushPort
    ];

    systemd.services.gatus.serviceConfig.EnvironmentFile = [
      uptime-ntfy.files.env.path
      uptime-push.files.env.path
    ];

    services.gatus = {
      enable = true;
      settings = {
        web = {
          address = "127.0.0.1";
          port = gatusPort;
        };
        ui.title = "THECLUSTER";
        # Events are capped by count; 500 covers a month of outages.
        storage = {
          type = "sqlite";
          path = "/var/lib/gatus/data.db";
          maximum-number-of-events = 500;
        };
        alerting.ntfy = {
          topic = "\${GATUS_NTFY_TOPIC}";
          priority = 4;
          default-alert.send-on-resolved = true;
        };
        external-endpoints = lib.concatLists (
          lib.mapAttrsToList (
            group:
            lib.mapAttrsToList (
              name: push:
              {
                inherit name group;
                token = "\${GATUS_PUSH_TOKEN}";
                # Each push is one result, so one failure is enough.
                alerts = ntfyAlerts {
                  failure-threshold = 1;
                  success-threshold = 1;
                };
              }
              // lib.optionalAttrs (push.heartbeat != null) { heartbeat.interval = push.heartbeat; }
            )
          ) cfg.pushes
        );
        endpoints =
          lib.optional (cfg.vip != null) (tcp "rosequartz" "apiserver VIP" "${cfg.vip}:6443")
          ++ lib.optional (cfg.gateway != null) (tcp "rosequartz" "gateway" "${cfg.gateway}:443")
          ++ lib.mapAttrsToList (n: a: tcp "apiserver" n "${a}:6443") cfg.apiservers
          ++ lib.mapAttrsToList (n: a: tcp "etcd" n "${a}:2379") cfg.etcd
          ++ lib.mapAttrsToList dns cfg.resolvers
          ++ lib.mapAttrsToList (n: svc: {
            name = n;
            group = "services";
            inherit (svc) url conditions;
            interval = "1m";
            alerts = lib.optionals svc.page (ntfyAlerts { });
          }) cfg.services
          ++ lib.mapAttrsToList (n: a: {
            name = n;
            group = "hosts";
            url = "icmp://${a}";
            interval = "1m";
            conditions = [ "[CONNECTED] == true" ];
          }) cfg.hosts;
      };
    };
  };
}
