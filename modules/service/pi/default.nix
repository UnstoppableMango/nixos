{
  _class = "clan.service";
  manifest.name = "raspberry-pi";
  manifest.readme = builtins.readFile ./README.md;

  # Hardware only. Resolvers are clan-wide and come from ../../dns, imported by
  # each machine's configuration.nix. This role used to carry a `nameservers`
  # setting as well, but networking.nameservers is a list, so the role's value
  # concatenated with the machine's instead of overriding it and every Pi ended
  # up leading with two resolvers that no longer answer.
  roles.pi4b = {
    description = "Raspberry Pi 4B";
    perInstance.nixosModule.imports = [ ./4b.nix ];
  };
}
