# zeus runs Hercules CI builds next to fifteen Ceph OSDs (4 GiB limit each)
# and has no swap. Without these limits the builds and the pods each assume the
# whole machine, and the kernel OOM killer picks among OSDs.
#
# The CI stack shares one slice whose ceiling the kubelet reserves, so
# the scheduler never hands that memory to pods.
let
  ciMemoryMax = 48;
in
{
  systemd.slices.ci = {
    description = "Nix builds, Hercules CI agents and harmonia";
    sliceConfig = {
      MemoryHigh = "40G";
      MemoryMax = "${toString ciMemoryMax}G";
      # Half the default weight, so kubelet and the OSDs win CPU contention.
      CPUWeight = 50;
      IOWeight = 50;
    };
  };

  # Builds run as children of nix-daemon, so its slice is where they land.
  systemd.services.nix-daemon.serviceConfig.Slice = "ci.slice";
  systemd.services.hercules-ci-agent-unmango.serviceConfig = {
    Slice = "ci.slice";
    MemoryMax = "8G";
  };
  systemd.services.hercules-ci-agent-unstoppablemango.serviceConfig = {
    Slice = "ci.slice";
    MemoryMax = "8G";
  };
  systemd.services.harmonia.serviceConfig = {
    Slice = "ci.slice";
    MemoryMax = "2G";
  };

  # 8 jobs x 4 cores fills the 32 threads once, rather than 32 x 32.
  nix.settings = {
    max-jobs = 8;
    cores = 4;
  };

  services.kubernetes.kubelet.extraConfig = {
    # The CI slice ceiling plus about 4 GiB for the rest of the host.
    systemReserved = {
      cpu = "4";
      memory = "${toString (ciMemoryMax + 4)}Gi";
    };
    kubeReserved = {
      cpu = "1";
      memory = "2Gi";
    };
    evictionHard."memory.available" = "2Gi";
  };
}
