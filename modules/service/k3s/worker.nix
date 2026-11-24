{ config, ... }:
let
  inherit (config.clan.core.vars.generators) k3s-token;
in
{
  imports = [ ./k3s.nix ];

  services.k3s = {
    role = "agent";
    tokenFile = k3s-token.files.token.path;
  };
}
