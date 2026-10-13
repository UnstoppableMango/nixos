{
  imports = [
    ./disk-config.nix
    ../../modules/memory-pressure
    ../../modules/pihole
  ];

  networking = {
    hostName = "pik8s1";
    defaultGateway = {
      address = "10.0.69.1";
      interface = "end0";
    };
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.101";
          prefixLength = 24;
        }
      ];
    };
  };

  pihole.enable = true;
}
