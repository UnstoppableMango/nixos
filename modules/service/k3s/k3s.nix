{ config, pkgs, ... }:
let
  inherit (config.clan.core.vars.generators) k3s-token;
in
{
  clan.core.vars.generators.k3s-token = {
    prompts.token.description = "K3s token";
    prompts.token.type = "hidden";
    prompts.token.persist = false;
    files.hash.secret = false;

    script = ''
      mkpasswd -m sha-512 < $prompts/token > $out/hash
    '';

    runtimeInputs = [ pkgs.mkpasswd ];
  };

  clan.core.vars.generators.k3s-agent-token = {
    prompts.token.description = "K3s agent token";
    prompts.token.type = "hidden";
    prompts.token.persist = false;
    files.hash.secret = false;

    script = ''
      mkpasswd -m sha-512 < $prompts/token > $out/hash
    '';

    runtimeInputs = [ pkgs.mkpasswd ];
  };

  # https://search.nixos.org/options?channel=unstable&query=k3s
  services.k3s = {
    # enable = true;
    tokenFile = k3s-token.files.hash.path;

    disable = [
      "traefik"
      "servicelb"
      "local-storage"
      "metrics-server"
    ];

    images = [
      config.services.k3s.package.airgap-images
    ];
  };
}
