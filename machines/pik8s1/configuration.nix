{
  hardware.facter.reportPath = ./facter.json;

  networking.interfaces.eth0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.1.101";
        prefixLength = 24;
      }
    ];
  };
}
