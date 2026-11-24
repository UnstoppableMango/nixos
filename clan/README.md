# clan

## rosequartz measurements

These figures size `rosequartz-cluster.nix`.

- Node capacity: apollo has 32 threads and 32 GiB, so memory runs out first; zeus has 32 threads and 125 GiB; gaea has 128 threads and 503 GiB.
- gaea sat at 109 pods against cairn's 110-pod default, with under half its CPU and a third of its memory requested.
- On the 4 GiB pis, an apiserver reached 2.7 GiB and was still climbing when the machine stopped responding, which took the local etcd member down with it.
  The machine that inherited the VIP did the same twenty minutes later.
- With a 1800M `MemoryHigh`, all three control-plane apiservers stalled at the throttle with swap 1886/1886 MiB used and `NRestarts=0`, serving nothing for hours.
  That is why the apiserver has `MemoryMax` alone.
- `MemoryMax = "5G"` leaves an 8 GiB pi about 3 GiB for etcd, the kubelet and the OS.
- radosgw keeps containerd's 1024 soft nofile limit and stops accepting on :443 under an ncps burst.
