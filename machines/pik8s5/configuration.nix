{
  hardware.facter.reportPath = ./facter.json;

  networking = {
    hostName = "pik8s5";
    defaultGateway.interface = "eth0";

    interfaces.eth0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.1.105";
          prefixLength = 24;
        }
      ];
    };
  };
}
