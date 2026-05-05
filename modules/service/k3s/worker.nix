{
  imports = [ ./k3s.nix ];

  # https://search.nixos.org/options?channel=unstable&query=k3s
  services.k3s = {
    role = "agent";
    serverAddr = "https://192.168.1.100:6443";
  };
}
