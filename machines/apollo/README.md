# apollo

## Measurements

- 32 threads and 32 GiB, with 31.2 GiB allocatable.
- Eight OSDs: six 14 TB drives and two NVMe.
- With ci-limits, the reservations were `memoryMax` + 4 GiB system-reserved plus 2 GiB kube-reserved, which left 11.2 GiB allocatable and no room for a third OSD.
  The CI slice could not also hold 12 GiB, so apollo is a storage host only, and gaea, at 504 GiB, runs CI.
- The GPU is a GTX 1060 (GP106, Pascal).
  NVIDIA 580 is the long-term branch for Pascal, supported until August 2028.
