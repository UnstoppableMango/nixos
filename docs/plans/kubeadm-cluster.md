# Plan: HA Control Plane via services.kubernetes (pik8s4–6 + agreus)

## Context

Building a new HA Kubernetes cluster using NixOS's built-in `services.kubernetes` module — fully declarative, no `kubeadm init/join` bootstrap steps. pik8s4–6 are the etcd + control-plane nodes on a new VLAN 10 (10.0.10.0/24). agreus is the admin host (kubectl, kubeconfig). Custom CA from `UnstoppableMango/pki` (Azure Key Vault) pre-provisioned via sops-nix. Flannel is built into the NixOS kubernetes module. pik8s1–3 are **not touched**.

Key finding: `services.kubernetes.easyCerts = true` does NOT support multi-master (`pki.nix` line 357: "easyCerts doesn't support multimaster clusters anyway atm"). We'll use `easyCerts = false` and provide all cert paths from sops secrets. This aligns with our custom CA requirement anyway.

---

## IP Addressing (VLAN 10 — 10.0.10.0/24)

| Node    | IP           | Interface |
|---------|--------------|-----------|
| pik8s4  | 10.0.10.4    | end0      |
| pik8s5  | 10.0.10.5    | end0      |
| pik8s6  | 10.0.10.6    | end0      |
| agreus  | 10.0.10.187  | (existing NIC) |
| API VIP | 10.0.10.100  | pfSense HAProxy |
| gateway | 10.0.10.1    | pfSense   |

**Note**: All Pi4B nodes will use `end0` (systemd predictable naming on NixOS). pik8s1–3 existing configs use `eth0` — left untouched since they're not being re-flashed.

---

## API Server VIP — pfSense HAProxy

pfSense has a HAProxy package. Configure it to load-balance `10.0.10.100:6443` → `10.0.10.4:6443`, `10.0.10.5:6443`, `10.0.10.6:6443`. This is done in the pfSense UI (out of scope for NixOS config) and provides the VIP with no dependency on the cluster being up first. No kube-vip needed.

---

## Out-of-scope (manual / pfSense)

1. Create VLAN 10 on pfSense, assign interface IP 10.0.10.1/24
2. Configure switch trunk/access ports for VLAN 10
3. Configure pfSense HAProxy: frontend 10.0.10.100:6443 → backend pik8s4-6:6443
4. pfSense firewall rules for the new VLAN and API access
5. Download CA cert + key from Azure Key Vault, encrypt with SOPS

---

## Files to Create

### `modules/service/kubeadm/default.nix`
Keep name `kubeadm` for the clan service (user-visible), but internally uses `services.kubernetes`:
```nix
{
  _class = "clan.service";
  manifest.name = "kubeadm";
  manifest.readme = builtins.readFile ./README.md;
  roles.control-plane = {
    description = "Kubernetes control plane node";
    perInstance.nixosModule = ./control-plane.nix;
  };
}
```

### `modules/service/kubeadm/control-plane.nix`
Shared NixOS module for all control-plane nodes. Contains:

**Options** (for per-node configuration from machine configs):
```nix
options.cluster.kubernetes = {
  advertiseAddress = lib.mkOption { type = lib.types.str; };  # per-node IP
  etcd = {
    advertiseClientUrls = lib.mkOption { type = lib.types.listOf lib.types.str; };
    initialAdvertisePeerUrls = lib.mkOption { type = lib.types.listOf lib.types.str; };
  };
};
```

**Config** (shared across all nodes):
- `services.kubernetes.roles = ["master"]`
- `services.kubernetes.masterAddress = "10.0.10.100"` (pfSense VIP)
- `services.kubernetes.easyCerts = false`
- `services.kubernetes.flannel.enable = true`
- `services.kubernetes.apiserver.advertiseAddress = config.cluster.kubernetes.advertiseAddress`
- `services.kubernetes.apiserver.etcd.servers` = all 3 etcd URLs
- Cert paths from sops secrets (see below)
- `services.etcd.enable = true` + cluster settings (initialCluster with all 3 nodes)
- `services.etcd.advertiseClientUrls` / `initialAdvertisePeerUrls` = from per-node options
- Firewall ports: 6443, 2379-2380, 10250-10252, 10257, 10259; UDP 8285/8472 (flannel)
- `boot.kernelModules = ["br_netfilter"]`
- `boot.kernel.sysctl` for ip_forward and bridge-nf-call-iptables

**Note on cert paths**: sops file paths are per-machine (encrypted per-machine age key), so `sopsFile` cannot be in the shared module. Preferred: create `sops/cluster/secrets/kubernetes.yaml` encrypted with pik8s4+pik8s5+pik8s6 age keys. This single file holds all cluster certs. Reference it from all three machine configs.

### `modules/service/kubeadm/README.md`
Brief description (required by clan manifest).

### `machines/pik8s5/disk-config.nix`
Identical to `machines/pik8s4/disk-config.nix`: GPT on `/dev/sda`, single XFS partition labeled `VAR`, mounted at `/var`. Explicit `fileSystems."/var"` with `lib.mkDefault`.

### `machines/pik8s6/disk-config.nix`
Same as pik8s5.

---

## Files to Modify

### `machines/pik8s4/configuration.nix`
```nix
{ lib, ... }: {
  imports = [ ./disk-config.nix ];
  hardware.facter.reportPath = ./facter.json;

  networking = {
    hostName = "pik8s4";
    defaultGateway = lib.mkForce { address = "10.0.10.1"; interface = "end0"; };
    nameservers = lib.mkForce [ "10.0.10.1" ];
    interfaces.end0 = {
      useDHCP = false;
      ipv4.addresses = [{ address = "10.0.10.4"; prefixLength = 24; }];
    };
  };

  # Per-node kubernetes/etcd settings
  cluster.kubernetes.advertiseAddress = "10.0.10.4";
  cluster.kubernetes.etcd.advertiseClientUrls = ["https://10.0.10.4:2379"];
  cluster.kubernetes.etcd.initialAdvertisePeerUrls = ["https://10.0.10.4:2380"];

  # SOPS: cluster cert file (encrypted for pik8s4+5+6 age keys)
  sops.secrets.k8s-certs.sopsFile = ../../sops/cluster/secrets/kubernetes.yaml;
}
```

### `machines/pik8s5/configuration.nix`
- Import `./disk-config.nix`
- Change interface from `eth0` → `end0`
- IP `10.0.10.5`, gateway `10.0.10.1` (`lib.mkForce`)
- `cluster.kubernetes.advertiseAddress = "10.0.10.5"`
- etcd URLs with 10.0.10.5
- Same sops cluster cert reference

### `machines/pik8s6/configuration.nix`
- Same as pik8s5 but IP `10.0.10.6`, etcd URLs 10.0.10.6

### `machines/agreus/configuration.nix`
- Change IP to `10.0.10.187`
- Override gateway to `10.0.10.1` (with appropriate `lib.mkForce`)
- Add `environment.systemPackages = with pkgs; [kubectl kubernetes-helm]` for cluster management

### `clan.nix`
1. Register module: `modules."@UnstoppableMango/kubeadm" = import ./modules/service/kubeadm;`
2. Split pik8s helper: `pik8sOld` for 1-3 (keep k3s tags), explicit entries for pik8s4-6 with `"kubeadm-control-plane"` tag (remove old `"control-plane"` tag from them)
3. Update `deploy.targetHost` for pik8s4-6 and agreus to new VLAN IPs
4. Add kubeadm inventory instance:
   ```nix
   kubeadm = {
     module.name = "@UnstoppableMango/kubeadm";
     module.input = "self";
     roles.control-plane.tags.kubeadm-control-plane = {};
   };
   ```

---

## SOPS Secrets

Create `sops/cluster/secrets/kubernetes.yaml` encrypted with pik8s4 + pik8s5 + pik8s6 age keys (all three can decrypt). Contains:
- `ca.crt` (from UnstoppableMango/pki via Azure KV)
- `ca.key`
- `apiserver.crt`, `apiserver.key`
- `apiserver-kubelet-client.crt`, `apiserver-kubelet-client.key`
- `controller-manager.crt`, `controller-manager.key`
- `scheduler.crt`, `scheduler.key`
- `etcd/ca.crt`, `etcd/peer.crt`, `etcd/peer.key`, `etcd/server.crt`, `etcd/server.key`
- `sa.pub`, `sa.key` (service account signing key pair)

Update `.sops.yaml` with path regex for `sops/cluster/secrets/`.

---

## PKI cert generation (manual, before deploy)

```bash
# Download from Azure KV
az keyvault secret show --vault-name <vault> --name k8s-ca-crt --query value -o tsv > ca.crt
az keyvault secret show --vault-name <vault> --name k8s-ca-key --query value -o tsv > ca.key

# Generate component certs signed by CA (use cfssl or openssl)
# Encrypt with sops
sops -e --age <pik8s4-age>,<pik8s5-age>,<pik8s6-age> kubernetes.yaml > sops/cluster/secrets/kubernetes.yaml
```

---

## Bootstrap Procedure

1. **pfSense**: VLAN 10, HAProxy for 10.0.10.100:6443 → pik8s4-6:6443
2. **Generate + encrypt k8s certs** (above)
3. **Flash SD cards + format SSDs** via nixos-anywhere:
   ```
   nix run github:nix-community/nixos-anywhere -- --flake '.#pik8sX' root@<current-IP>
   ```
4. **Deploy** — NixOS boots, `services.kubernetes` + `services.etcd` start automatically with full config
5. **Kubeconfig** — copy from pik8s4 `/etc/kubernetes/cluster-admin.kubeconfig` to agreus

No `kubeadm init`. No `kubeadm join`. Fully declarative.

---

## Cert Configuration in control-plane.nix

The `services.kubernetes` cert options (verify exact names against nixpkgs source):
```nix
services.kubernetes = {
  caFile = config.sops.secrets."k8s-ca-crt".path;
  apiserver = {
    tlsCertFile = config.sops.secrets."k8s-apiserver-crt".path;
    tlsKeyFile = config.sops.secrets."k8s-apiserver-key".path;
    clientCaFile = config.sops.secrets."k8s-ca-crt".path;
    serviceAccountKeyFile = config.sops.secrets."k8s-sa-pub".path;
    serviceAccountSigningKeyFile = config.sops.secrets."k8s-sa-key".path;
    kubeletClientCertFile = config.sops.secrets."k8s-apiserver-kubelet-client-crt".path;
    kubeletClientKeyFile = config.sops.secrets."k8s-apiserver-kubelet-client-key".path;
    etcd.certFile = config.sops.secrets."k8s-etcd-client-crt".path;
    etcd.keyFile = config.sops.secrets."k8s-etcd-client-key".path;
    etcd.caFile = config.sops.secrets."k8s-etcd-ca-crt".path;
  };
  controllerManager = {
    tlsCertFile = ...;
    tlsKeyFile = ...;
    serviceAccountKeyFile = ...;
  };
  # etc.
};

services.etcd = {
  certFile = config.sops.secrets."k8s-etcd-server-crt".path;
  keyFile = config.sops.secrets."k8s-etcd-server-key".path;
  trustedCaFile = config.sops.secrets."k8s-etcd-ca-crt".path;
  peerCertFile = config.sops.secrets."k8s-etcd-peer-crt".path;
  peerKeyFile = config.sops.secrets."k8s-etcd-peer-key".path;
  peerTrustedCaFile = config.sops.secrets."k8s-etcd-ca-crt".path;
  peerClientCertAuth = true;
  clientCertAuth = true;
};
```

NixOS k8s module source for reference:
`/nix/store/0v3hh34akm0mb8616w6ga06b3ngvjskq-source/nixos/modules/services/cluster/kubernetes/`

---

## Verification

- `make check` — flake evaluates without errors for all systems
- `nix build .#nixosConfigurations.pik8s4.config.system.build.toplevel` — builds clean
- After deploy: `kubectl get nodes` from agreus shows pik8s4/5/6 as Ready, control-plane
- `kubectl get pods -n kube-system` shows flannel pods running
- `etcdctl endpoint health --endpoints=https://10.0.10.4:2379,https://10.0.10.5:2379,https://10.0.10.6:2379` from any node

---

## Key Reference Files

- Pattern for disk SSD: `machines/pik8s4/disk-config.nix`
- Pattern for clan service: `modules/service/k3s/default.nix`, `control-plane.nix`
- Pi networking: `modules/service/pi/4b.nix` (gateway/nameservers need `lib.mkForce` override in machine configs for new VLAN)
