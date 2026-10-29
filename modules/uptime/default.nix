# Gatus, on a machine outside rosequartz, watching rosequartz and the LAN
# services around it. Nothing inside the cluster can report the cluster
# being down, so this runs where that failure does not reach.
#
# Checks are declared here rather than in a UI, so the config stays
# read-only NixOS like everything else on the machine. The page is served on
# `uptime.port`, open on the LAN.
{ config, lib, ... }:
let
  cfg = config.uptime;

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
  options.uptime = {
    enable = lib.mkEnableOption "the Gatus uptime checker";

    port = lib.mkOption {
      type = lib.types.port;
      default = 8080;
      description = "Port the status page is served on.";
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
          };
        }
      );
      default = { };
      example = {
        nextcloud.url = "https://cloud.thecluster.io/status.php";
      };
      description = "Services the cluster hosts, by name, each checked over HTTP.";
    };
  };

  config = lib.mkIf cfg.enable {
    services.gatus = {
      enable = true;
      openFirewall = true;
      settings = {
        web.port = cfg.port;
        ui.title = "THECLUSTER";
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
          }) cfg.services
          ++ lib.mapAttrsToList (n: a: {
            name = n;
            group = "hosts";
            # The module grants CAP_NET_RAW, which ICMP needs.
            url = "icmp://${a}";
            interval = "1m";
            conditions = [ "[CONNECTED] == true" ];
          }) cfg.hosts;
      };
    };
  };
}
