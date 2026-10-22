{ config, ... }:
{
  imports = [
    ./disk-config.nix
    ../../modules/kiosk
    ../../modules/uptime
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

  # Outside rosequartz so it still answers, and the screen still shows it,
  # while the cluster is down. Hosts, the VIP, apiservers and etcd members
  # come from the inventory in clan.nix.
  uptime = {
    enable = true;
    gateway = "10.0.69.200";
    resolvers = {
      pik8s1 = "10.0.69.101";
      pik8s2 = "10.0.69.102";
      pik8s6 = "10.0.69.106";
      "pihole (in-cluster, .201)" = "10.0.69.201";
      "pihole (in-cluster, .202)" = "10.0.69.202";
    };
  };

  kiosk = {
    enable = true;
    url = "http://localhost:${toString config.uptime.port}";
  };
}
