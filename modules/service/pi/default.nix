{
  _class = "clan.service";
  manifest.name = "raspberry-pi";
  roles.pi4b.perInstance.nixosModule = ./4b.nix;
}
