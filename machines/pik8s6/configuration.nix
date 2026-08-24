{ lib, ... }:
{
  imports = [ ./disk-config.nix ];

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

  # This node joined after the initial quorum was formed. mkForce wins over
  # the rosequartz cluster module's cluster-wide "new" default
  # (clan/rosequartz-cluster.nix), which has no per-machine override for
  # this option.
  cluster.cairn.etcd.initialClusterState = lib.mkForce "existing";
}
