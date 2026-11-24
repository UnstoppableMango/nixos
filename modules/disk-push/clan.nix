# Authenticates the push with the vars Gatus shares.
{ config, lib, ... }:
let
  inherit (config.clan.core.vars.generators) uptime-push uptime-tls;
in
{
  imports = [
    ../uptime/push-vars.nix
    ./default.nix
  ];

  diskPush = {
    tokenFile = lib.mkDefault uptime-push.files.token.path;
    pubkeyFile = lib.mkDefault uptime-tls.files.pubkey.path;
  };
}
