{
  hardware.facter.reportPath = ./facter.json;

  networking.defaultGateway.interface = "end0";

  networking.interfaces.end0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.1.104";
        prefixLength = 24;
      }
    ];
  };
}
