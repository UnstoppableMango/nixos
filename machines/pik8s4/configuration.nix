{
  # imports = [ ./disk-config.nix ];

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

  cluster.rosequartz = {
    interface = "end0";
    advertiseAddress = "192.168.1.104";
    keepalivedPriority = 100;
    etcd.advertiseClientUrls = [ "https://192.168.1.104:2379" ];
    etcd.initialAdvertisePeerUrls = [ "https://192.168.1.104:2380" ];
  };

}
