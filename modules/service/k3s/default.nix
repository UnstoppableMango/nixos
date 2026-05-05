{
  _class = "clan.service";
  manifest.name = "k3s";
  manifest.readme = builtins.readFile ./README.md;

  roles.worker = {
    description = "Kubernetes worker node";
    perInstance.nixosModule = ./worker.nix;
  };

  roles.control-plane = {
    description = "Kubernetes control plane node";
    perInstance.nixosModule = ./control-plane.nix;
  };
}
