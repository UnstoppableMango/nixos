# rosequartz: pik8s7-9 as an HA control plane behind a keepalived VIP, pik8s4-5
# as etcd-only members, and the x86 machines as workers.
let
  # A 4 GiB pi cannot hold the apiserver.
  controlPlane = [
    "pik8s7"
    "pik8s8"
    "pik8s9"
  ];

  etcdOnly = [
    "pik8s4"
    "pik8s5"
  ];

  nodes = builtins.filter (m: !builtins.elem m etcdOnly) (builtins.attrNames machines);

  machines = {
    # Every apiserver machine is also an etcd member: flannel reaches etcd through
    # the raw VIP, which HAProxy does not front.
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

    # 250 is the ceiling: each node's /24 podCIDR has no address past 254.
    apollo = {
      role = "worker";
      ip = "10.0.69.12";
      # The runner pods mount a node-local nix store, so they only run
      # where `arcRunnerStore.enable` holds.
      nodeLabels = {
        "thecluster.lan/ci-runner" = "true";
        # The GTX 1060. The `nvidia` containerd handler exists only here.
        "nvidia.com/gpu.present" = "true";
      };
      maxPods = 150;
    };

    zeus = {
      role = "worker";
      ip = "10.0.69.10";
      maxPods = 200;
    };

    gaea = {
      role = "worker";
      ip = "10.0.69.11";
      # The runner pods mount a node-local nix store, so they only run
      # where `arcRunnerStore.enable` holds.
      nodeLabels."thecluster.lan/ci-runner" = "true";
      maxPods = 250;
    };
  };
in
{
  vip = "10.0.69.100";


  # Keeps instance ids at `rosequartz-pki`, `rosequartz-etcd`, etc.
  instancePrefix = "rosequartz-";

  # One minor at a time, per cairn's docs/UPGRADES.md.
  versions.kubernetes = "1.37";

  inherit machines;

  services = {
    pki = {
      # Cairn's "cairn" default would mint a parallel CA and take the cluster down.
      generatorPrefix = "rosequartz";

      # The cluster CA is an intermediate, so OpenSSL clients need its root.
      caChain = [ (builtins.readFile ../certs/unmango-authority.crt) ];
    };

    # With "new", a reflashed member bootstraps a cluster of its own.
    etcd.initialClusterState = "existing";

    etcd.autoJoin = true;

    # Removed by whichever member deploys first. Drop a name once every member
    # has been deployed with it.
    etcd.removedMembers = [ "pik8s6" ];

    etcd.extraModules = [
      # etcd must never swap: a member paged out to zram misses raft heartbeats,
      # and the cluster ends up with no leader.
      { systemd.services.etcd.serviceConfig.MemorySwapMax = 0; }
    ];

    apiserver.machines = controlPlane;
    coredns.machines = controlPlane;
    kubelet.machines = nodes;
    network.machines = nodes;
    kubeconfig.machines = nodes;
    inoculant.machines = nodes;

    apiserver.extraModules = [
      # The public issuer lets Entra verify tokens for workload identity. Its JWKS
      # is a static file in UnstoppableMango/pki: copy `kubectl get --raw
      # /openid/v1/jwks` over oidc/rosequartz/openid/v1/jwks on a key change.
      #
      # Only the first --service-account-issuer signs. Every apiserver must accept
      # the public issuer before any signs with it, so a later change makes it
      # serviceAccountIssuer and keeps the old one in extraOpts.
      {
        services.kubernetes.apiserver.extraOpts = "--service-account-issuer=https://unmangocrl.blob.core.windows.net/oidc/rosequartz";
      }

      # Bounded, the apiserver dies instead of the machine and its etcd member.
      # `MemoryMax` alone: a lower `MemoryHigh` stalls it once zram fills, and a
      # stalled apiserver never fails `/readyz` or restarts.
      {
        systemd.services.kube-apiserver = {
          serviceConfig.MemoryMax = "5G";
          # Otherwise systemd stops restarting the unit after five kills.
          unitConfig.StartLimitIntervalSec = 0;
        };
      }

      # kubelogin uses the public `kubernetes` client from UnstoppableMango/iam.
      # The `oidc:` prefix keeps realm groups from colliding with built-ins such as
      # system:masters. An unreachable issuer only disables OIDC logins.
      (
        { pkgs, ... }:
        let
          authentication = pkgs.writeText "authentication-config.json" (
            builtins.toJSON {
              apiVersion = "apiserver.config.k8s.io/v1";
              kind = "AuthenticationConfiguration";
              jwt = [
                {
                  issuer = {
                    url = "https://auth.thecluster.io/realms/thecluster";
                    audiences = [ "kubernetes" ];
                  };
                  claimMappings = {
                    username = {
                      claim = "preferred_username";
                      prefix = "oidc:";
                    };
                    groups = {
                      claim = "groups";
                      prefix = "oidc:";
                    };
                  };
                }
              ];
            }
          );
        in
        {
          services.kubernetes.apiserver.extraOpts = "--authentication-config=${authentication}";
        }
      )
    ];

    # `coredns.nodeNames` stays unset: the image reaches a node only through its
    # kubelet's pre-start seeding, so other nodes must run the same generation.
    kubelet.extraModules = [
      # radosgw never raises its 1024 soft nofile limit and stops accepting under
      # an ncps burst. TODO: drop once cairn sets it (UnstoppableMango/cairn#93).
      { systemd.services.containerd.serviceConfig.LimitNOFILE = 1048576; }

      # Handler for the-cluster's nested-containers RuntimeClass.
      # TODO: drop once cairn can declare runtime handlers (UnstoppableMango/cairn#96).
      {
        virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc-cgroup-writable =
          {
            runtime_type = "io.containerd.runc.v2";
            cgroup_writable = true;
            options.SystemdCgroup = true;
          };
      }

      # Flannel runs without IP masquerade, so scrapes also arrive from pod IPs.
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
