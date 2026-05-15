{
  _class = "clan.service";
  manifest.name = "raspberry-pi";

  roles.pi4b = {
    description = "Raspberry Pi 4B";
    perInstance.nixosModule = ./4b.nix;
  };
}
