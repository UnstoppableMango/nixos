{
  imports = [
    ./disk-config.nix
    ../../modules/dns
  ];

  networking = {
    hostName = "pik8s5";
    defaultGateway = {
      address = "10.0.69.1";
      interface = "end0";
    };
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.105";
          prefixLength = 24;
        }
      ];
    };
  };
}
