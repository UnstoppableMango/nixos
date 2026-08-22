{
  _class = "clan.service";
  manifest.name = "k3s";
  manifest.readme = builtins.readFile ./README.md;

  roles.worker = {
    description = "Kubernetes worker node";

    interface =
      { lib, ... }:
      {
        options.serverAddr = lib.mkOption {
          type = lib.types.str;
          description = "URL of the k3s control plane server this worker joins (e.g. https://10.0.0.1:6443).";
        };
      };

    perInstance =
      { settings, ... }:
      {
        nixosModule = {
          imports = [ ./worker.nix ];
          services.k3s.serverAddr = settings.serverAddr;
        };
      };
  };

  roles.control-plane = {
    description = "Kubernetes control plane node";

    interface =
      { lib, ... }:
      {
        options.serverAddr = lib.mkOption {
          type = lib.types.str;
          description = "URL this node advertises as the k3s control plane server (e.g. https://10.0.0.1:6443).";
        };

        options.tlsSans = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = "Additional --tls-san entries (e.g. other control plane IPs/hostnames) for the apiserver cert.";
        };
      };

    perInstance =
      { settings, ... }:
      {
        nixosModule = {
          imports = [ ./control-plane.nix ];
          services.k3s.serverAddr = settings.serverAddr;
          services.k3s.extraFlags = map (san: "--tls-san=${san}") settings.tlsSans;
        };
      };
  };
}
