{
  hardware.facter.reportPath = ./facter.json;

  networking = {
    hostName = "pik8s4";
    defaultGateway.interface = "end0";

    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.1.104";
          prefixLength = 24;
        }
      ];
    };
  };
}
