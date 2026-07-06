{
  imports = [ ./disk-config.nix ];

  hardware.facter.reportPath = ./facter.json;

  networking = {
    hostName = "pik8s1";
    defaultGateway.interface = "eth0";

    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.1.101";
          prefixLength = 24;
        }
      ];
    };
  };
}
