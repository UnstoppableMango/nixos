{ config, ... }:
let
  inherit (config.clan.core.vars.generators) k3s-token;
in
{
  imports = [ ./k3s.nix ];

  # https://search.nixos.org/options?channel=unstable&query=k3s
  services.k3s = {
    role = "server";
    tokenFile = k3s-token.files.token.path;
  };

  environment.systemPackages = with pkgs; [
    etcd # For etcdctl
  ];
}
