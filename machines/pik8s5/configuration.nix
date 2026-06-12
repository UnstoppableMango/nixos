{
  imports = [ ./disk-config.nix ];

  hardware.facter.reportPath = ./facter.json;

  networking = {
    hostName = "pik8s5";
    defaultGateway.interface = "end0";

    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.1.105";
          prefixLength = 24;
        }
      ];
    };
  };

  cluster.pinkdiamond = {
    interface = "end0";
    advertiseAddress = "192.168.1.105";
    keepalivedPriority = 90;
    etcd.advertiseClientUrls = [ "https://192.168.1.105:2379" ];
    etcd.initialAdvertisePeerUrls = [ "https://192.168.1.105:2380" ];
  };

}
