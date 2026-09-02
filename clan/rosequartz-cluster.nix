# THECLUSTER's vanilla-Kubernetes cluster, "rosequartz": pik8s1, pik8s2 and
# pik8s4-6 as an HA control plane behind a keepalived VIP, with pik8s3,
# agreus, pollux, castor, zeus, and gaea as workers. Lowered
# by cairn's `cairn.clusters` option tree (flakeModules/cluster/lower.nix)
# into the same per-service inventory instances this used to be hand-wired
# as in clan.nix.
{
  vip = "10.0.69.100";

  # `clusterName` defaults to the attribute name ("rosequartz" in flake.nix),
  # so it isn't set here.

  # Two-machine-cluster-flake naming, kept stable rather than left to the
  # (single-cluster) auto-detected default, so instance ids stay exactly
  # `rosequartz-pki`, `rosequartz-etcd`, etc.
  instancePrefix = "rosequartz-";

  machines = {
    # pik8s1 and pik8s2 joined after pik8s4-6 formed the cluster, so they take
    # the lowest VIP priorities and carry an `initialClusterState = "existing"`
    # override in their own machines/<name>/configuration.nix.
    #
    # They bring the quorum to five: odd, and one more failure tolerated than
    # the three it replaces. pik8s3 is a worker rather than a sixth
    # control-plane machine, which would make the quorum even and buy no
    # tolerance. An apiserver that is not also an etcd member is not a shape
    # cairn models: `etcd-client-cert` comes from the etcd member module, and
    # HAProxy fronts only the apiserver port, so flannel reaching etcd through
    # the raw VIP assumes whoever holds it runs etcd locally.
    pik8s1 = {
      role = "control-plane";
      ip = "10.0.69.101";
      keepalivedPriority = 70;
    };
    pik8s2 = {
      role = "control-plane";
      ip = "10.0.69.102";
      keepalivedPriority = 60;
    };
    pik8s3 = {
      role = "worker";
      ip = "10.0.69.103";
    };

    pik8s4 = {
      role = "control-plane";
      ip = "10.0.69.104";
      # Staggered so pik8s4 wins the VIP by default.
      keepalivedPriority = 100;
    };
    pik8s5 = {
      role = "control-plane";
      ip = "10.0.69.105";
      keepalivedPriority = 90;
    };
    pik8s6 = {
      role = "control-plane";
      ip = "10.0.69.106";
      keepalivedPriority = 80;
    };

    agreus = {
      role = "worker";
      ip = "10.0.69.187";
    };

    pollux = {
      role = "worker";
      ip = "10.0.69.14";
    };

    castor = {
      role = "worker";
      ip = "10.0.69.13";
    };

    zeus = {
      role = "worker";
      ip = "10.0.69.10";
    };

    gaea = {
      role = "worker";
      ip = "10.0.69.11";
    };
  };

  services = {
    pki = {
      # Reuse the existing rosequartz-* var generators (and the CA behind
      # them) rather than minting a fresh set under cairn's default "cairn-"
      # prefix.
      generatorPrefix = "rosequartz";
    };

    loadbalancer = {
      enable = true;
      interface = "end0";

      # `machines` defaults to every control-plane machine. pik8s1 and pik8s2
      # stay out while their UniFi 24p ports are still VLAN 1 untagged with
      # VLAN 20 tagged: VRRP runs on the cluster-wide `interface`, so
      # keepalived there would advertise on VLAN 1 and put the VIP on the
      # wrong network. Drop this pin once their ports become VLAN 20 access
      # ports and their `end0.20` collapses into `end0`.
      machines = [
        "pik8s4"
        "pik8s5"
        "pik8s6"
      ];
    };

    # inoculant defaults to every machine in the cluster; the existing config
    # scopes it to the control plane only, so pin that explicitly rather than
    # silently picking up agreus.
    inoculant.machines = [
      "pik8s1"
      "pik8s2"
      "pik8s4"
      "pik8s5"
      "pik8s6"
    ];

    flux = {
      enable = true;
      url = "https://github.com/UnstoppableMango/the-cluster";
      branch = "main";
      path = "./clusters/rosequartz";
    };
  };
}
