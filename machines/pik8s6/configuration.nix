{
  hardware.facter.reportPath = ./facter.json;

  networking.interfaces.eth0 = {
    useDHCP = false;
    ipv4.addresses = [
      {
        address = "192.168.1.106";
        prefixLength = 24;
      }
    ];
  };
}
