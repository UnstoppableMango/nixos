# Memory pressure visibility for the 4 GiB pi control-plane machines, which
# run etcd next to a kube-apiserver whose resident set is a live Go heap of
# over 2 GiB.
#
# These machines carry no swap, by choice. The apiserver's memory is watch
# caches and compiled CRD schemas that the garbage collector walks in full, so
# there are no cold pages to bank: anything paged out is faulted straight back
# in. Swap buys latency rather than capacity here, and it converts the
# apiserver's `MemoryMax` in clan/rosequartz-cluster.nix from an exact bound
# into an open one, since a cgroup's swap ceiling is a separate limit that
# defaults to unbounded. Without it the apiserver is killed at a predictable
# size and restarts in seconds, which is the failure this control plane wants.
#
# etcd carries `MemorySwapMax = 0` in the cluster config regardless, so a
# machine that gains swap later still keeps its raft heartbeats off it.
{ ... }:
{
  # `/proc/pressure/*` exists only with this set, and those counters are what
  # separate a machine reclaiming steadily from one about to stop responding.
  # Reading resident set size alone cannot tell the two apart.
  #
  # This does not put systemd-oomd in charge of system.slice. Left to pick a
  # victim by pressure it may choose etcd, and losing the etcd member is the
  # failure being prevented; the apiserver's own cgroup ceiling is the
  # deterministic control.
  boot.kernelParams = [ "psi=1" ];
}
