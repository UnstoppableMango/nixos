# gaea

## Measurements

- 128 threads and 503 GB, shared by OSDs, the Hercules agents and the Actions runner pods.

## Hardware

- An EPYC 7502 (Zen 2) rack box with its firmware in UEFI mode.
- eno2 stays unconfigured.
  It carried the previous cluster's 10.69.0.0/16 network on a VLAN 69 subinterface.
