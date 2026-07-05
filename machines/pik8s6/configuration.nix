{
  imports = [ ./disk-config.nix ];

  hardware.facter.reportPath = ./facter.json;
  hardware.raspberry-pi."4".usbBoot.enable = true;

  networking = {
    hostName = "pik8s6";
    defaultGateway = {
      address = "10.0.69.1";
      interface = "end0";
    };
    nameservers = [ "10.0.69.1" ];

    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.106";
          prefixLength = 24;
        }
      ];
    };
  };

  cluster.rosequartz = {
    interface = "end0";
    advertiseAddress = "10.0.69.106";
    keepalivedPriority = 80;
    etcd.advertiseClientUrls = [ "https://10.0.69.106:2379" ];
    etcd.initialAdvertisePeerUrls = [ "https://10.0.69.106:2380" ];
    etcd.initialClusterState = "existing";
  };
}
