# THECLUSTER's vanilla-Kubernetes cluster, "rosequartz": pik8s7-9 as an HA
# control plane behind a keepalived VIP, pik8s4-5 as etcd-only members, and
# pik8s3, agreus, pollux, castor, iris, apollo, zeus, and gaea as workers.
# Lowered by cairn's `cairn.clusters` option tree
# (flakeModules/cluster/lower.nix) into the same per-service inventory
# instances this used to be hand-wired as in clan.nix.
let
  # The 8 GiB pis. Everything a control-plane machine runs besides etcd is
  # pinned here, since a 4 GiB pi cannot hold the apiserver.
  controlPlane = [
    "pik8s7"
    "pik8s8"
    "pik8s9"
  ];

  # The 4 GiB pis left in the quorum. They run etcd and nothing else.
  etcdOnly = [
    "pik8s4"
    "pik8s5"
  ];

  # Every Kubernetes node: every machine but the etcd-only ones, which run no
  # kubelet and so are not nodes at all. Derived, so a new worker needs no
  # entry here.
  nodes = builtins.filter (m: !builtins.elem m etcdOnly) (builtins.attrNames machines);

  machines = {
    # The quorum stays at five: odd, and one more failure tolerated than three.
    # pik8s3 is a worker rather than a sixth etcd member, which would make the
    # quorum even and buy no tolerance. Every apiserver machine is also an
    # etcd member: HAProxy fronts only the apiserver port, so flannel reaching
    # etcd through the raw VIP assumes whoever holds it runs etcd locally.
    pik8s3 = {
      role = "worker";
      ip = "10.0.69.103";
    };

    # `etcdOnly`. Their `control-plane` role only places them in etcd's
    # default machine list; every other control-plane service is pinned to
    # `controlPlane` under `services`.
    pik8s4 = {
      role = "control-plane";
      ip = "10.0.69.104";
    };
    pik8s5 = {
      role = "control-plane";
      ip = "10.0.69.105";
    };

    pik8s7 = {
      role = "control-plane";
      ip = "10.0.69.107";
      # Staggered so pik8s7 wins the VIP by default.
      keepalivedPriority = 100;
    };
    pik8s8 = {
      role = "control-plane";
      ip = "10.0.69.108";
      keepalivedPriority = 90;
    };
    pik8s9 = {
      role = "control-plane";
      ip = "10.0.69.109";
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

    iris = {
      role = "worker";
      ip = "10.0.69.15";
    };

    # The three x86 workers raise cairn's 110-pod default, which the pi
    # nodes keep. Each is sized against its own CPU and memory rather than
    # set uniformly; 250 is the ceiling either way, since each node gets a
    # /24 podCIDR and a pod admitted past 254 would have no address.
    apollo = {
      role = "worker";
      ip = "10.0.69.12";
      # The runner pods mount a node-local nix store, so they only run
      # where `arcRunnerStore.enable` holds.
      nodeLabels = {
        "thecluster.lan/ci-runner" = "true";
        # The GTX 1060. The nvidia-device-plugin chart's default affinity and
        # the-cluster's nvidia RuntimeClass both select on this label, and the
        # `nvidia` containerd handler exists only here
        # (machines/apollo/configuration.nix).
        "nvidia.com/gpu.present" = "true";
      };
      # 32 threads, 32 GiB: the memory is what runs out first here.
      maxPods = 150;
    };

    zeus = {
      role = "worker";
      ip = "10.0.69.10";
      # 32 threads, 125 GiB, minus the ci.slice ceiling modules/ci-limits
      # reserves from the kubelet.
      maxPods = 200;
    };

    gaea = {
      role = "worker";
      ip = "10.0.69.11";
      # The runner pods mount a node-local nix store, so they only run
      # where `arcRunnerStore.enable` holds.
      nodeLabels."thecluster.lan/ci-runner" = "true";
      # 128 threads, 503 GiB. It sat at 109 pods against the 110 cap with
      # under half its CPU and a third of its memory requested.
      maxPods = 250;
      # The first node on nix-snapshotter, so pods here can run
      # `nix:0/nix/store/...` images off the node's store. Switching
      # snapshotters discards the images containerd already holds, so drain
      # the node before deploying this.
      nixSnapshotter = true;
    };
  };
in
{
  vip = "10.0.69.100";

  # `clusterName` defaults to the attribute name ("rosequartz" in flake.nix),
  # so it isn't set here.

  # Two-machine-cluster-flake naming, kept stable rather than left to the
  # (single-cluster) auto-detected default, so instance ids stay exactly
  # `rosequartz-pki`, `rosequartz-etcd`, etc.
  instancePrefix = "rosequartz-";

  # Kubernetes and etcd come from kubepkgs.
  # Bump one minor at a time, per cairn's docs/UPGRADES.md.
  versions.kubernetes = "1.37";

  inherit machines;

  services = {
    pki = {
      # Reuse the existing rosequartz-* var generators (and the CA behind
      # them) rather than minting a fresh set under cairn's default "cairn-"
      # prefix.
      generatorPrefix = "rosequartz";

      # The cluster CA (thecluster.io) is an intermediate. Without its root,
      # OpenSSL-based clients in pods reject kube-root-ca.crt.
      caChain = [ (builtins.readFile ../certs/unmango-authority.crt) ];
    };

    # The quorum formed long ago, so a member always joins it. With "new", a
    # member starting on an empty data directory (after a reflash) bootstraps
    # a cluster of its own instead, and the others reject it on cluster ID.
    etcd.initialClusterState = "existing";

    # Register a machine with no etcd data as a learner before its etcd
    # starts, and promote it once caught up, rather than an `etcdctl member
    # add` by hand. Machines already holding data are left alone.
    etcd.autoJoin = true;

    # Members that have left the inventory, removed from etcd by whichever
    # remaining member is deployed first. A name can go once every member has
    # been deployed with it.
    etcd.removedMembers = [ "pik8s6" ];

    etcd.extraModules = [
      # etcd must never swap. Its latency budget is a raft heartbeat, and a
      # member paged out to the zram from modules/memory-pressure misses them:
      # the symptom is `took too long` on every apply, repeated pre-vote
      # rounds, and finally a cluster with no leader while every member is
      # nominally running. The apiserver on the same machine is what creates
      # the memory pressure, so excluding etcd from the relief is the point.
      { systemd.services.etcd.serviceConfig.MemorySwapMax = 0; }
    ];

    # pik8s4-5 stay etcd members (the default, every `control-plane`
    # machine) and run nothing else. The services that default to every
    # control-plane machine are pinned to the 8 GiB pis, and the ones that
    # default to every machine to the Kubernetes nodes.
    apiserver.machines = controlPlane;
    coredns.machines = controlPlane;
    kubelet.machines = nodes;
    network.machines = nodes;
    kubeconfig.machines = nodes;
    inoculant.machines = nodes;

    apiserver.extraModules = [
      # On the 4 GiB pis that used to run it, an apiserver reached 2.7 GiB and
      # was still climbing when the machine stopped responding, which took the
      # local etcd member with it; the quorum that would let the apiserver
      # settle then could not form, and the machine that inherited the VIP did
      # the same thing twenty minutes later. The 8 GiB pis have the room for
      # it, but not without limit.
      #
      # Bounded, the apiserver is what dies instead of the machine: HAProxy
      # takes it out of rotation on the `/readyz` check, the other members keep
      # the quorum, and it comes back into a cluster that has a leader.
      #
      # `MemoryMax` alone, deliberately. A `MemoryHigh` below it throttles
      # instead of killing: reclaim runs, the zram from
      # modules/memory-pressure fills, and once it is full there is nowhere
      # left to reclaim to, so the process stalls at the throttle instead of
      # ever reaching `MemoryMax`. Measured on all three machines at once,
      # pinned to the byte at a 1800M `MemoryHigh` with swap 1886/1886 MiB
      # used, `NRestarts=0`, and an apiserver that had served nothing for
      # hours. A stalled apiserver is worse than a killed one, because nothing
      # restarts it and `/readyz` never answers for HAProxy to act on.
      {
        systemd.services.kube-apiserver = {
          # Leaves an 8 GiB pi about 3 GiB for etcd, the kubelet and the OS.
          serviceConfig.MemoryMax = "5G";
          # Without this, systemd's default rate limit stops restarting the
          # unit after five kills and leaves the machine with no apiserver at
          # all, which is the outcome the ceiling exists to avoid.
          unitConfig.StartLimitIntervalSec = 0;
        };
      }
    ];

    # `coredns.nodeNames` stays unset, so the pods run on the machines that
    # bootstrap the manifests. The generated Deployment pulls
    # `coredns:<store hash>` with `imagePullPolicy: Never`, and that image
    # reaches a node only through its own kubelet's pre-start seeding, from the
    # generation that node runs. Naming machines here that are not on the same
    # generation as the bootstrapping ones leaves the pods on
    # `ErrImageNeverPull`, so moving CoreDNS off the control plane needs the
    # target nodes to match generations, not just to run kubelets.
    kubelet.extraModules = [
      # Containers inherit containerd's soft nofile limit, systemd's 1024 when
      # unset. radosgw never raises its own, and at 1024 it stops accepting on
      # :443 under an ncps burst. Drop this once the cairn input sets the same
      # default (UnstoppableMango/cairn#93).
      { systemd.services.containerd.serviceConfig.LimitNOFILE = 1048576; }

      # Handler for the nested-containers RuntimeClass in the-cluster. Pods in
      # a user namespace that run their own container runtime (dind, podman,
      # buildkitd) need a writable /sys/fs/cgroup, which runc then delegates to
      # the namespace's root. Drop this once cairn can declare runtime handlers
      # (UnstoppableMango/cairn#96).
      {
        virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc-cgroup-writable =
          {
            runtime_type = "io.containerd.runc.v2";
            cgroup_writable = true;
            options.SystemdCgroup = true;
          };
      }

      # node-exporter from the-cluster's kube-prometheus-stack, scraped on the
      # host IP. Flannel runs without IP masquerade, so a scrape arrives from
      # the Prometheus pod's IP as well as from a node's.
      (
        { config, ... }:
        {
          networking.firewall.extraCommands = ''
            iptables -A nixos-fw -p tcp --dport 9100 -s 10.0.69.0/24 -j nixos-fw-accept
            iptables -A nixos-fw -p tcp --dport 9100 -s ${config.services.kubernetes.clusterCidr} -j nixos-fw-accept
          '';
        }
      )
    ];

    loadbalancer = {
      enable = true;
      machines = controlPlane;
      # Every control-plane machine reaches VLAN 20 untagged on `end0`, so VRRP
      # advertises on the right network everywhere.
      interface = "end0";
    };

    flux = {
      enable = true;
      machines = controlPlane;
      url = "https://github.com/UnstoppableMango/the-cluster";
      branch = "main";
      path = "./clusters/rosequartz";
    };
  };
}
