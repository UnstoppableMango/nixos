{
  imports = [
    ./disk-config.nix
    ../../modules/dns
    ../../modules/kiosk
    ../../modules/nix
  ];

  networking = {
    hostName = "pik8s3";
    defaultGateway = {
      address = "10.0.69.1";
      interface = "end0";
    };
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.103";
          prefixLength = 24;
        }
      ];
    };
  };

  kiosk = {
    enable = true;
    url = "https://thecluster.lan";
  };

  # Covers the kiosk slice's MemoryMax plus headroom for the OS.
  cluster.cairn.kubelet.systemReserved.memory = "1Gi";

}
