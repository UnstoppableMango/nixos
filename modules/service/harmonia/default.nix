{ lib, ... }:
let
  # Both roles import this: servers derive the private half from it, clients read
  # `pub-key.value` at eval time. `deploy = false` keeps the private half off the
  # clients, which only ever need the public one.
  varsForInstance = instanceName: pkgs: {
    clan.core.vars.generators."harmonia-${instanceName}" = {
      share = true;
      files.sign-key.secret = true;
      files.sign-key.deploy = false;
      files.pub-key.secret = false;
      script = ''
        ${pkgs.nix}/bin/nix-store --generate-binary-cache-key ${instanceName}-1 \
          $out/sign-key \
          $out/pub-key
      '';
    };
  };
in
{
  _class = "clan.service";
  manifest.name = "harmonia";
  manifest.description = "Serve a machine's own nix store to the clan as a signed binary cache";
  manifest.categories = [ "System" ];
  manifest.readme = builtins.readFile ./README.md;

  roles.server = {
    description = "A machine whose nix store is served to the clan";

    interface.options = {
      port = lib.mkOption {
        type = lib.types.port;
        default = 5000;
        description = "Port harmonia listens on.";
      };

      address = lib.mkOption {
        type = lib.types.nullOr lib.types.str;
        default = null;
        description = ''
          Host or address clients dial to reach this server. Defaults to
          `<machine>.<clan domain>`, which requires that name to resolve on the
          LAN; set an IP to avoid depending on DNS.
        '';
      };

      priority = lib.mkOption {
        type = lib.types.int;
        default = 20;
        description = ''
          Substituter priority, advertised in `nix-cache-info` and applied to the
          URL clients use. Lower wins; cache.nixos.org is 40.
        '';
      };
    };

    perInstance =
      { settings, instanceName, ... }:
      {
        nixosModule =
          { config, pkgs, ... }:
          let
            shared = "harmonia-${instanceName}";
          in
          {
            imports = [ (varsForInstance instanceName pkgs) ];

            # The shared generator does not deploy its private half, so copy it
            # into a per-machine generator that does.
            clan.core.vars.generators."${shared}-private" = {
              dependencies = [ shared ];
              files.sign-key.secret = true;
              script = ''
                cp $in/${shared}/sign-key $out/sign-key
              '';
            };

            services.harmonia.cache = {
              enable = true;

              signKeyPaths = [
                config.clan.core.vars.generators."${shared}-private".files.sign-key.path
              ];

              # The nixpkgs module derives harmonia.socket's ListenStream from
              # `bind`, so this is what actually moves the port.
              settings.bind = "[::]:${toString settings.port}";
              settings.priority = settings.priority;
            };

            networking.firewall.allowedTCPPorts = [ settings.port ];
          };
      };
  };

  roles.client = {
    description = "A machine that substitutes from the harmonia servers";

    perInstance =
      { instanceName, roles, ... }:
      {
        nixosModule =
          { config, pkgs, ... }:
          let
            domain = config.clan.core.settings.domain;
            dotDomain = if domain != null then ".${domain}" else "";

            # A server is also a client, and substituting from itself is a
            # pointless round trip through the daemon.
            others = lib.filterAttrs (name: _: name != config.networking.hostName) roles.server.machines;

            url =
              name: machine:
              let
                inherit (machine.settings) port priority;
                host = if machine.settings.address != null then machine.settings.address else "${name}${dotDomain}";
              in
              "http://${host}:${toString port}?priority=${toString priority}";
          in
          {
            imports = [ (varsForInstance instanceName pkgs) ];

            nix.settings = {
              extra-substituters = lib.mapAttrsToList url others;

              extra-trusted-public-keys = [
                config.clan.core.vars.generators."harmonia-${instanceName}".files.pub-key.value
              ];

              # Servers include a workstation that is regularly asleep or off.
              # Without a short timeout every substituter miss stalls on it.
              connect-timeout = lib.mkDefault 5;
            };
          };
      };
  };
}
