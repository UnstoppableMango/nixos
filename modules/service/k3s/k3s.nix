{ config, ... }:
let
  inherit (config.clan.core.vars.generators) k3s-token;
in
{
  # https://docs.k3s.io/cli/token
  clan.core.vars.generators.k3s-token = {
    prompts = {
      token.description = "K3s token";
      token.type = "hidden";
    };

    files.token.secret = true;

    script = ''
      mv "$prompts/token" "$out/token"
    '';
  };

  # https://search.nixos.org/options?channel=unstable&query=k3s
  services.k3s = {
    enable = true;
    serverAddr = "https://192.168.1.100:6443";
    tokenFile = k3s-token.files.token.path;

    extraFlags = [
      "--tls-san=192.168.1.104" # Match the existing config
      "--tls-san=192.168.1.100"
      "--disable-cloud-controller"
      "--disable-helm-controller"
      "--disable-network-policy"
      "--kubelet-arg=allowed-unsafe-sysctls=net.ipv4.conf.all.src_valid_mark"
    ];

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
