{
  # https://search.nixos.org/options?channel=unstable&query=k3s
  services.k3s = {
    # enable = true; # WIP
    disable = [
      "traefik"
      "servicelb"
      "local-storage"
      "metrics-server"
    ];
  };
}
