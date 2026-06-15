{
  # imports = [ ./disk-config.nix ];

  hardware.facter.reportPath = ./facter.json;

  networking = {
    hostName = "pik8s6";
    defaultGateway.interface = "end0";

    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.1.106";
          prefixLength = 24;
        }
      ];
    };
  };

  cluster.rosequartz = {
    interface = "end0";
    advertiseAddress = "192.168.1.106";
    keepalivedPriority = 80;
    etcd.advertiseClientUrls = [ "https://192.168.1.106:2379" ];
    etcd.initialAdvertisePeerUrls = [ "https://192.168.1.106:2380" ];
  };

}
