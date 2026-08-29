# THECLUSTER's vanilla-Kubernetes cluster, "rosequartz": pik8s4/5/6 as an HA
# control plane behind a keepalived VIP, agreus, pollux, castor, zeus, and
# gaea as workers. Lowered
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
    };

    # inoculant defaults to every machine in the cluster; the existing config
    # scopes it to the control plane only, so pin that explicitly rather than
    # silently picking up agreus.
    inoculant.machines = [
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
