# Memory pressure handling for the 4 GiB pi control-plane machines, which run
# etcd next to a kube-apiserver whose watch caches grow past 2.5 GiB.
#
# With no swap the kernel has nowhere to put cold anonymous pages, so reclaim
# has nothing to reclaim and a `MemoryHigh` ceiling can only throttle. With no
# PSI, `/proc/pressure/memory` does not exist and every systemd-oomd unit is
# skipped on its `ConditionPathExists`. A machine under pressure therefore
# stops answering ssh rather than losing a process, and its etcd member goes
# quiet with it: the survivors cannot reach a quorum, so the apiservers retry
# against a leaderless cluster, grow faster, and take the next machine down.
#
# zram gives reclaim somewhere to go, which is what makes the apiserver's
# `MemoryHigh` in clan/rosequartz-cluster.nix do anything before its
# `MemoryMax` kills the process.
{ ... }:
{
  # systemd-oomd's units carry `ConditionPathExists=/proc/pressure/memory`,
  # which the kernel only creates with this set. Pressure metrics are also
  # what distinguishes "reclaiming steadily" from "about to stop responding"
  # when reading a machine that is still up.
  #
  # This does not put systemd-oomd in charge of system.slice. Left to pick a
  # victim by pressure it may choose etcd, and losing the etcd member is the
  # failure being prevented; the apiserver's own cgroup ceiling is the
  # deterministic control.
  boot.kernelParams = [ "psi=1" ];

  zramSwap = {
    enable = true;
    algorithm = "zstd";
    # Uncompressed ceiling, not an allocation. zstd holds around 3:1 on
    # apiserver heap, so the device backs appreciably more than it reserves.
    memoryPercent = 50;
  };

  boot.kernel.sysctl = {
    # Paging to memory costs far less than the default 60 assumes, and reclaim
    # should reach for zram before it evicts the page cache the kubelet and
    # containerd are reading through.
    "vm.swappiness" = 180;
    # Readahead buys nothing when the backing store has no seek penalty.
    "vm.page-cluster" = 0;
  };

  # The kubelet refuses to start at all when it finds swap enabled. Pods stay
  # on whatever the kubelet's own swap policy allows; what this is for is etcd
  # and the apiserver, which are systemd services and reach zram regardless.
  services.kubernetes.kubelet.extraConfig.failSwapOn = false;
}
