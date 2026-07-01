# VLAN Segmentation: Personal LAN vs Homelab

## Context

Currently all devices share 192.168.1.0/24 (flat L2). Goal: isolate k8s cluster nodes into a dedicated homelab VLAN so personal traffic and homelab traffic are on separate L2 domains. Doing this now (before rosequartz is deployed) avoids IP changes post-cert-deployment.

## VLAN Scheme

| VLAN | Name | Subnet | Gateway |
|------|------|--------|---------|
| 1 (native) | Personal | 192.168.1.0/24 | 192.168.1.1 |
| 20 | Homelab | 10.0.69.0/24 | 10.0.69.1 |

No CIDR conflicts: k8s service CIDR defaults to 10.0.0.0/24, pod CIDR to 10.244.0.0/16 — neither overlaps 10.0.69.0/24.

## New IP Addresses

| Node | Old IP | New IP |
|------|--------|--------|
| pik8s4 | 192.168.1.104 | 10.0.69.104 |
| pik8s5 | 192.168.1.105 | 10.0.69.105 |
| pik8s6 | 192.168.1.106 | 10.0.69.106 |
| agreus | 192.168.1.187 | 10.0.69.187 |
| rosequartz VIP | 192.168.1.100 | 10.0.69.100 |

## Phase 1: Switch/Router Config (manual, out-of-band)

### pfSense SBC
1. Add VLAN 20 sub-interface on the Unifi uplink NIC
2. Assign 10.0.69.1/24 to VLAN 20 interface
3. Enable DHCP for 10.0.69.0/24 (optional; nodes use static)
4. Firewall rules:
   - Homelab → internet: allow
   - Personal → homelab port 22 (SSH): allow
   - Personal → homelab port 6443 (kubectl): allow
   - Homelab → personal: block (or restrict to specific services)
   - Storage traffic stays intra-VLAN 20 (Ceph replication doesn't route)

### Unifi 24p (via UniFi Controller)
1. Create Network: "Homelab", VLAN 20
2. pik8s4/5/6 ports: set to VLAN 20 untagged (access port)
3. agreus port: set to VLAN 20 untagged (access port)
4. pfSense uplink port: trunk — tagged VLAN 1 + VLAN 20
5. GS108T uplink port: trunk — tagged VLAN 1 + VLAN 20

### GS108T
1. Uplink port to Unifi: 802.1Q trunk, pass VLAN 1 (tagged) + VLAN 20 (tagged)
2. hades (workstation) port: PVID 1, VLAN 1 untagged (access)
3. Other ports: VLAN 1 untagged unless they need homelab access

## Phase 2: NixOS Config Changes

### machines/pik8s4/configuration.nix
```nix
networking = {
  hostName = "pik8s4";
  defaultGateway = {
    address = "10.0.69.1";  # was missing!
    interface = "end0";
  };
  nameservers = [ "10.0.69.1" ];  # pfSense homelab gateway; replace with CoreDNS VIP once cluster up
  interfaces.end0 = {
    useDHCP = false;
    ipv4.addresses = [{
      address = "10.0.69.104";
      prefixLength = 24;
    }];
  };
};
cluster.rosequartz = {
  interface = "end0";
  advertiseAddress = "10.0.69.104";
  keepalivedPriority = 100;
  etcd.advertiseClientUrls = [ "https://10.0.69.104:2379" ];
  etcd.initialAdvertisePeerUrls = [ "https://10.0.69.104:2380" ];
};
```

### machines/pik8s5/configuration.nix
Same pattern: IP 10.0.69.105, priority 90.

### machines/pik8s6/configuration.nix
Same pattern: IP 10.0.69.106, priority 80.

### machines/agreus/configuration.nix
- Add static IP config for the homelab interface (currently no interface stanza):
```nix
networking = {
  hostName = "agreus";
  useDHCP = false;
  defaultGateway = {
    address = "10.0.69.1";
    interface = "<iface>";  # check facter.json for interface name
  };
  nameservers = [ "10.0.69.1" ];  # pfSense homelab gateway; replace with CoreDNS VIP once cluster up
  interfaces.<iface>.ipv4.addresses = [{
    address = "10.0.69.187";
    prefixLength = 24;
  }];
};
cluster.rosequartz.advertiseAddress = "10.0.69.187";
```
Note: check `machines/agreus/facter.json` for the ethernet interface name (likely `enp*` or `eth0`).

### clan.nix
Update `deploy.targetHost` and rosequartz settings:
```nix
# pik8s4/5/6 targetHost entries:
deploy.targetHost = "root@10.0.69.104";  # 105, 106

# agreus:
deploy.targetHost = "root@10.0.69.187";

# inventory.instances.rosequartz:
roles.control-plane.settings.vip = "10.0.69.100";
roles.control-plane.machines.pik8s4.settings.ip = "10.0.69.104";
roles.control-plane.machines.pik8s5.settings.ip = "10.0.69.105";
roles.control-plane.machines.pik8s6.settings.ip = "10.0.69.106";
roles.worker.machines.agreus.settings.ip = "10.0.69.187";
```

## Phase 3: Cert Regen

All rosequartz certs include node IPs in SANs. After IP changes, regenerate:
```
clan vars generate rosequartz
```
This re-runs all cert generators. Existing cert files are replaced.

## Deploy Order (avoid losing SSH access)

Use `nixos-rebuild boot` (not switch) to stage configs, then change switch port, then reboot:

For each node:
1. `nixos-rebuild boot --target-host root@<old-ip> --flake .#<machine>` — stages new config, no immediate effect
2. Change Unifi port to VLAN 20 in controller
3. Reboot node — comes up with new IP on correct VLAN

Verify after each node before proceeding to next. Deploy pik8s4 → pik8s5 → pik8s6 → agreus.

## Verification

1. `ping 10.0.69.104` from hades — tests routing through pfSense
2. `ssh root@10.0.69.104` — confirms SSH accessible from personal VLAN
3. `curl -k https://10.0.69.100:6443` — confirms VIP reachable after full cluster deploy
4. `nix flake check` — confirm config builds clean
