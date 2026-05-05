{
  imports = [ ./k3s.nix ];

  # https://search.nixos.org/options?channel=unstable&query=k3s
  services.k3s = {
    disableAgent = true;
    role = "server";
  };
}
