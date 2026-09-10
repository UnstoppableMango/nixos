{ lib, ... }:
{
  imports = [
    ./disk-config.nix
    ../../modules/dns
    ../../modules/nix
  ];

  # Transitional dual-homing. The UniFi 24p port carries VLAN 1 untagged and
  # VLAN 20 tagged, so this machine keeps its old address and default route
  # while gaining the VLAN 20 address rosequartz advertises for it
  # (clan/rosequartz-cluster.nix). Once every cluster path is confirmed over
  # 10.0.69.0/24, the port becomes a VLAN 20 access port and the VLAN 1
  # address and `end0.20` here collapse into a plain `end0` on VLAN 20.
  networking = {
    hostName = "pik8s2";
    defaultGateway = {
      address = "192.168.1.1";
      interface = "end0";
    };
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "192.168.1.102";
          prefixLength = 24;
        }
      ];
    };

    vlans."end0.20" = {
      id = 20;
      interface = "end0";
    };

    interfaces."end0.20" = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.102";
          prefixLength = 24;
        }
      ];
    };
  };

  # This node joined after the initial quorum was formed. mkForce wins over
  # the rosequartz cluster module's cluster-wide "new" default
  # (clan/rosequartz-cluster.nix), which has no per-machine override for
  # this option.
  cluster.cairn.etcd.initialClusterState = lib.mkForce "existing";
}
