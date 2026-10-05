{ ... }:
{
  imports = [
    ./disk-config.nix
    ../../modules/dns
    ../../modules/memory-pressure
    ../../modules/nix
  ];

  # The SSD's JMicron JMS578 bridge (Sabrent enclosure) drops off the bus
  # under UAS on the Pi 4's USB 3 ports, which held it to a USB 2 port where
  # etcd's fsyncs queued behind reads. Plain usb-storage keeps it on USB 3.
  # https://forums.raspberrypi.com/viewtopic.php?f=28&t=245931
  boot.kernelParams = [ "usb-storage.quirks=152d:a578:u" ];

  networking = {
    hostName = "pik8s1";
    defaultGateway = {
      address = "10.0.69.1";
      interface = "end0";
    };
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.101";
          prefixLength = 24;
        }
      ];
    };
  };
}
