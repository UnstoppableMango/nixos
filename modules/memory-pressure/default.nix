# No swap, by choice: the apiserver's heap has no cold pages, so swap buys
# latency, and it makes `MemoryMax` an open bound since a cgroup's swap
# ceiling defaults to unbounded.
{ ... }:
{
  # PSI counters tell steady reclaim from a machine about to stop responding.
  # Not systemd-oomd: picking by pressure, it may kill etcd.
  boot.kernelParams = [ "psi=1" ];
}
