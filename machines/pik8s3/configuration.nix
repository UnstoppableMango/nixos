{
  imports = [ ./disk-config.nix ];

  networking = {
    hostName = "pik8s3";
    defaultGateway = {
      address = "10.0.69.1";
      interface = "end0";
    };
    nameservers = [ "10.0.69.1" ];

    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.103";
          prefixLength = 24;
        }
      ];
    };
  };
}
