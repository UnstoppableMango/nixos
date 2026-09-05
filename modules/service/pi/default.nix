{
  _class = "clan.service";
  manifest.name = "raspberry-pi";
  manifest.readme = builtins.readFile ./README.md;

  # Hardware only. Resolvers are clan-wide and come from ../../dns, imported by
  # each machine's configuration.nix. Setting `networking.nameservers` here would
  # not work: it is a list, so a role-level value concatenates with the machine's
  # rather than overriding it, and the role's entries would lead the resolver
  # order on every Pi.
  roles.pi4b = {
    description = "Raspberry Pi 4B";
    perInstance.nixosModule.imports = [ ./4b.nix ];
  };
}
