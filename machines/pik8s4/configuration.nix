{
  hardware.facter.reportPath = ./facter.json;

  networking = {
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
