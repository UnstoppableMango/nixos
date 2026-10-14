# Pi-hole on the host, outside rosequartz, so the LAN keeps a filtering
# resolver while the cluster is down. Mirrors the-cluster's
# apps/pihole/base/helm-release-pihole.yml, which this is meant to replace.
{ config, lib, ... }:
let
  cfg = config.pihole;
  inherit (config.clan.core.vars.generators) pihole-admin;
in
{
  options.pihole = {
    enable = lib.mkEnableOption "Pi-hole as a LAN resolver";

    interface = lib.mkOption {
      type = lib.types.str;
      default = config.networking.defaultGateway.interface;
      defaultText = lib.literalExpression "config.networking.defaultGateway.interface";
      description = "Interface Pi-hole answers DNS on.";
    };

    gatewayAddress = lib.mkOption {
      type = lib.types.str;
      default = "10.0.69.200";
      description = ''
        Address every `thecluster.lan` name resolves to: the nginx-gateway
        LoadBalancer in rosequartz (the-cluster
        infrastructure/controllers/nginx-gateway-system/rosequartz).
      '';
    };
  };

  config = lib.mkIf cfg.enable {
    # One password for every Pi-hole, so the web UI login is the same on each.
    clan.core.vars.generators.pihole-admin = {
      share = true;
      prompts.password = {
        description = "Pi-hole web UI password";
        type = "hidden";
      };
      files.env.secret = true;
      script = ''
        # FTL reads any setting from an FTLCONF_<path> variable, and takes
        # `webserver.api.password` in plain text, hashing it itself. Quoted
        # and escaped so systemd's EnvironmentFile parsing passes every
        # character through.
        value=$(sed -e 's/[\\"$`]/\\&/g' "$prompts/password")
        printf '%s="%s"\n' FTLCONF_webserver_api_password "$value" > "$out/env"
      '';
    };

    services.pihole-ftl = {
      enable = true;
      openFirewallDNS = true;
      openFirewallWebserver = true;
      queryLogDeleter.enable = true;

      lists = [
        {
          url = "https://raw.githubusercontent.com/StevenBlack/hosts/master/hosts";
          description = "Steven Black's unified hosts list, Pi-hole's default";
        }
        {
          url = "https://raw.githubusercontent.com/Perflyst/PiHoleBlocklist/master/SmartTV.txt";
          description = "Smart TV telemetry, Samsung ACR among it";
        }
      ];

      settings = {
        dns = {
          upstreams = [
            "1.1.1.1"
            "1.0.0.1"
          ];
          domain.name = "thecluster.lan";
          interface = cfg.interface;
          # LOCAL, the default, refuses queries from subnets the host has no
          # interface on, and hades and the rest of VLAN 1 reach this one
          # through pfSense. BIND also keeps FTL off the wildcard address, which
          # systemd-resolved's stub on 127.0.0.53:53 would otherwise collide
          # with.
          # BIND only binds addresses the interface already has when FTL
          # starts, so the unit waits for the network below.
          listeningMode = "BIND";
        };

        misc.dnsmasq_lines = [
          # Every name in the zone is an HTTPRoute behind the rosequartz
          # gateway. The in-cluster piholes get these one at a time from
          # external-dns, which needs a writable pihole.toml; NixOS keeps this
          # one read-only, so the zone is a wildcard instead.
          "address=/thecluster.lan/${cfg.gatewayAddress}"
        ];

        # timesyncd keeps the clock; FTL's NTP client and server would fight it.
        ntp = {
          ipv4.active = false;
          ipv6.active = false;
          sync.active = false;
        };

        resolver.resolveIPv6 = false;

        webserver.interface.theme = "default-darker";
      };
    };

    services.pihole-web = {
      enable = true;
      # The default, pi.hole, which FTL answers with its own address. A name
      # in thecluster.lan would hit the wildcard and land on the gateway.
      ports = [ "80" ];
    };

    systemd.services.pihole-ftl = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig.EnvironmentFile = pihole-admin.files.env.path;
    };
  };
}
