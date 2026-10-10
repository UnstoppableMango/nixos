{
  imports = [
    ./disk-config.nix
    ../../modules/memory-pressure
  ];

  networking = {
    hostName = "pik8s7";
    defaultGateway = {
      address = "10.0.69.1";
      interface = "end0";
    };
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.107";
          prefixLength = 24;
        }
      ];
    };
  };
}
