{
  hardware.facter.reportPath = ./facter.json;

  networking.defaultGateway.interface = "eth0";

  networking.interfaces.eth0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.1.102";
        prefixLength = 24;
      }
    ];
  };
}
