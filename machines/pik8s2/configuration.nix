{
  imports = [ ./disk-config.nix ];

  networking = {
    hostName = "pik8s2";
    defaultGateway.interface = "eth0";

    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.1.102";
          prefixLength = 24;
        }
      ];
    };
  };
}
