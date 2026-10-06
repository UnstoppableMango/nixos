{
  config,
  lib,
  pkgs,
  ...
}:
let
  cfg = config.cephClusterNetwork;
  k8s = config.services.kubernetes;

  subnet = "10.0.70.0/24";
  prefixLength = 24;

  # multus reads NetworkAttachmentDefinitions with the kubelet's identity: the
  # Node authorizer covers the pod reads and status updates, and the-cluster's
  # infrastructure/controllers/multus grants system:nodes the NADs.
  multusKubeconfig = k8s.lib.mkKubeConfig "multus" k8s.kubelet.kubeconfig;
in
{
  options.cephClusterNetwork = {
    enable = lib.mkEnableOption "the Ceph cluster network on the SFP+ aggregator";

    interface = lib.mkOption {
      type = lib.types.str;
      description = "SFP+ port cabled to the aggregator.";
    };

    address = lib.mkOption {
      type = lib.types.str;
      description = "This host's address in ${subnet}, held on the ceph0 macvlan shim.";
    };

    rangeStart = lib.mkOption {
      type = lib.types.str;
      description = "First address this host hands to OSD pods.";
    };

    rangeEnd = lib.mkOption {
      type = lib.types.str;
      description = "Last address this host hands to OSD pods.";
    };

    mtu = lib.mkOption {
      type = lib.types.int;
      default = 9000;
      description = "MTU on the port, the shim, and the OSD pod interfaces. The aggregator must have jumbo frames enabled.";
    };
  };

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.networking.useNetworkd;
        message = "cephClusterNetwork configures the SFP+ port through systemd-networkd.";
      }
    ];

    # The port carries no address. A macvlan parent cannot reach its own
    # macvlan children, so the host's address lives on a bridge-mode sibling
    # of the OSD interfaces instead. That keeps the pod network able to reach
    # a local OSD's cluster address.
    systemd.network = {
      netdevs."30-ceph0" = {
        netdevConfig = {
          Name = "ceph0";
          Kind = "macvlan";
          MTUBytes = toString cfg.mtu;
        };
        macvlanConfig.Mode = "bridge";
      };

      networks."30-ceph-cluster-port" = {
        matchConfig.Name = cfg.interface;
        networkConfig = {
          MACVLAN = [ "ceph0" ];
          LinkLocalAddressing = "no";
        };
        linkConfig = {
          MTUBytes = toString cfg.mtu;
          RequiredForOnline = "no";
        };
      };

      networks."30-ceph0" = {
        matchConfig.Name = "ceph0";
        address = [ "${cfg.address}/${toString prefixLength}" ];
        networkConfig.LinkLocalAddressing = "no";
        linkConfig.RequiredForOnline = "no";
      };
    };

    # multus wraps flannel, so every pod still gets its flannel interface
    # first. The delegate must match cairn's network service, which sets the
    # same list at mkDefault.
    services.kubernetes.kubelet.cni = {
      packages = [ pkgs.multus-cni ];
      config = [
        {
          cniVersion = "0.3.1";
          name = "multus-cni-network";
          type = "multus";
          kubeconfig = multusKubeconfig;
          confDir = "/etc/cni/multus/net.d";
          cniDir = "/var/lib/cni/multus";
          binDir = "/opt/cni/bin";
          delegates = [
            {
              name = "cni0";
              type = "flannel";
              cniVersion = "0.3.1";
              delegate = {
                isDefaultGateway = true;
                hairpinMode = true;
                bridge = "cni0";
              };
            }
          ];
        }
      ];
    };

    # The config behind the rook-ceph/ceph-cluster NetworkAttachmentDefinition,
    # which has no spec.config of its own. host-local keeps its leases on tmpfs:
    # an unclean reboot never releases them, and every OSD pod is recreated
    # after a boot anyway.
    environment.etc."cni/multus/net.d/ceph-cluster.conf".text = builtins.toJSON {
      cniVersion = "0.3.1";
      name = "ceph-cluster";
      type = "macvlan";
      master = cfg.interface;
      mode = "bridge";
      inherit (cfg) mtu;
      ipam = {
        type = "host-local";
        dataDir = "/run/cni/ceph-cluster";
        ranges = [
          [
            {
              inherit subnet;
              inherit (cfg) rangeStart rangeEnd;
            }
          ]
        ];
      };
    };

    # /etc/cni/net.d is a symlink into the store, and containerd's watch on it
    # does not see the link swapped. Running containers survive the restart.
    systemd.services.containerd.restartTriggers = [ config.environment.etc."cni/net.d".source ];
  };
}
