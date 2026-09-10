{ settings, instanceName, ... }:
{
  nixosModule =
    { config, pkgs, ... }:
    let
      shared = "harmonia-${instanceName}";
    in
    {
      imports = [ (import ./vars.nix instanceName pkgs) ];

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
}
