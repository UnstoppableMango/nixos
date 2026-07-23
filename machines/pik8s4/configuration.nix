{
  imports = [ ./disk-config.nix ];

  networking = {
    hostName = "pik8s4";
    defaultGateway = {
      address = "10.0.69.1";
      interface = "end0";
    };
    nameservers = [ "10.0.69.1" ];

    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.104";
          prefixLength = 24;
        }
      ];
    };
  };

  cluster.rosequartz = {
    interface = "end0";
    advertiseAddress = "10.0.69.104";
    keepalivedPriority = 100;
    etcd.advertiseClientUrls = [ "https://10.0.69.104:2379" ];
    etcd.initialAdvertisePeerUrls = [ "https://10.0.69.104:2380" ];
  };
}
