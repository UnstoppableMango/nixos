# Pi-hole outside rosequartz, so the LAN keeps a filtering resolver while the
# cluster is down. Meant to replace the-cluster's apps/pihole.
{
  config,
  lib,
  pkgs,
  ...
}:
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
    clan.core.vars.generators.pihole-admin = {
      share = true;
      prompts.password = {
        description = "Pi-hole web UI password";
        type = "hidden";
      };
      files.env.secret = true;
      runtimeInputs = [ pkgs.gnused ];
      script = ''
        # FTL hashes a plain-text `webserver.api.password` itself. Quoted so
        # EnvironmentFile parsing passes every character through.
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
          # LOCAL refuses VLAN 1, which reaches this through pfSense, and the wildcard
          # address collides with systemd-resolved's stub on 127.0.0.53:53.
          # NONE writes no listening config, so the lines below supply it.
          # `bind-dynamic`, since FTL's `bind-interfaces` never retries, and
          # pik8s2 and pik8s6 came up listening on nothing.
          listeningMode = "NONE";
        };

        misc.dnsmasq_lines = [
          "interface=${cfg.interface}"
          "bind-dynamic"
          # pihole.toml is read-only here, so external-dns cannot write single records.
          "address=/thecluster.lan/${cfg.gatewayAddress}"
        ];

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
      # A thecluster.lan name would hit the wildcard and land on the gateway.
      ports = [ "80" ];
    };

    systemd.services.pihole-ftl = {
      wants = [ "network-online.target" ];
      after = [ "network-online.target" ];
      serviceConfig.EnvironmentFile = pihole-admin.files.env.path;
    };
  };
}
