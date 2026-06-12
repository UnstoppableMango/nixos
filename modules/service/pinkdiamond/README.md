# pinkdiamond

HA Kubernetes control plane using NixOS `services.kubernetes`.

## VIP

keepalived VRRP, HAProxy proxies :6443 → apiserver :6444

## PKI

Certs pre-provisioned to `sops/cluster/secrets/kubernetes.yaml` before deployment.
See that file's structure in the module source for required keys.
