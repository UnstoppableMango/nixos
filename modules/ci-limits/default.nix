# Resource limits for hosts that run Hercules CI builds next to rook-ceph OSDs
# and other rosequartz pods, without swap. Unbounded, the builds and the pods
# each assume the whole machine and the kernel OOM killer picks among OSDs.
#
# The CI stack shares one slice whose ceiling the kubelet reserves, so the
# scheduler never hands that memory to pods.
{ config, lib, ... }:
let
  cfg = config.ciLimits;
  inherit (lib) mkOption types;
  ciService = memoryMax: {
    Slice = "ci.slice";
    MemoryMax = "${toString memoryMax}G";
  };
in
{
  options.ciLimits = {
    memoryMax = mkOption {
      type = types.ints.positive;
      description = "Hard memory ceiling of `ci.slice`, in GiB. Throttling starts at five sixths of it.";
    };

    agentMemoryMax = mkOption {
      type = types.ints.positive;
      description = "Memory ceiling of each Hercules CI agent, which evaluates in-process, in GiB.";
    };

    maxJobs = mkOption {
      type = types.ints.positive;
      description = "nix `max-jobs`. With `cores`, sized so jobs x cores is the thread count.";
    };

    cores = mkOption {
      type = types.ints.positive;
      description = "nix `cores` per build.";
    };

    reservedCpu = mkOption {
      type = types.ints.positive;
      description = "CPUs the kubelet reserves for the host.";
    };
  };

  config = {
    systemd.slices.ci = {
      description = "Nix builds, Hercules CI agents and harmonia";
      sliceConfig = {
        MemoryHigh = "${toString (cfg.memoryMax * 5 / 6)}G";
        MemoryMax = "${toString cfg.memoryMax}G";
        # Half the default weight, so kubelet and the OSDs win contention.
        CPUWeight = 50;
        IOWeight = 50;
      };
    };

    # Builds run as children of nix-daemon, so its slice is where they land.
    systemd.services.nix-daemon.serviceConfig.Slice = "ci.slice";
    systemd.services.hercules-ci-agent-unmango.serviceConfig = ciService cfg.agentMemoryMax;
    systemd.services.hercules-ci-agent-unstoppablemango.serviceConfig = ciService cfg.agentMemoryMax;
    systemd.services.harmonia.serviceConfig = ciService 2;

    nix.settings = {
      max-jobs = cfg.maxJobs;
      inherit (cfg) cores;
    };

    services.kubernetes.kubelet.extraConfig = {
      # The CI slice ceiling plus about 4 GiB for the rest of the host.
      systemReserved = {
        cpu = toString cfg.reservedCpu;
        memory = "${toString (cfg.memoryMax + 4)}Gi";
      };
      kubeReserved = {
        cpu = "1";
        memory = "2Gi";
      };
      evictionHard."memory.available" = "2Gi";
    };
  };
}
