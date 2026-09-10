{ instanceName, roles, ... }:
{
  nixosModule =
    {
      config,
      lib,
      pkgs,
      ...
    }:
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
      imports = [ (import ./vars.nix instanceName pkgs) ];

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
}
