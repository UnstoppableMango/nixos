{
  _class = "clan.service";
  manifest.name = "base";
  manifest.readme = builtins.readFile ./README.md;

  roles.default = {
    description = "Configuration every machine in the clan carries";
    perInstance.nixosModule.imports = [
      ../../dns
      ../../nix
    ];
  };
}
