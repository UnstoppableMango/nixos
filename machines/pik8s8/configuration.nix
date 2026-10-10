{
  imports = [
    ./disk-config.nix
    ../../modules/memory-pressure
  ];

  networking = {
    hostName = "pik8s8";
    defaultGateway = {
      address = "10.0.69.1";
      interface = "end0";
    };
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.108";
          prefixLength = 24;
        }
      ];
    };
  };
}
