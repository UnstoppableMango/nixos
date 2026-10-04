# The resolvers every machine in the clan uses.
#
# 10.0.69.201 and 10.0.69.202 are the only resolvers on the network that carry
# the `thecluster.lan` zone. The pfSense gateways (192.168.1.1 on VLAN 1,
# 10.0.69.1 on VLAN 20) answer NXDOMAIN for names in it, so a machine pointed
# at its gateway cannot resolve the `ncps.thecluster.lan` substituter in
# ../cache and silently falls through to the public caches instead.
#
# Both addresses front the pihole deployment in rosequartz, so they share a
# failure domain. Each machine's gateway is therefore a second resolver for
# public names only, in its own resolved scope so it never sees
# thecluster.lan. With both piholes down, public names keep resolving, and the
# cluster nodes can still pull the pihole image that brings DNS back
# (the-cluster#4458). NETWORK.md, "DNS and service addressing", has the
# reasoning.
{ config, lib, ... }:
let
  gateway = config.networking.defaultGateway;
in
{
  networking.nameservers = [
    "10.0.69.201"
    "10.0.69.202"
  ];

  # Every machine runs systemd-resolved, so the pair above lands in the global
  # scope and anything a link supplies is scoped to that link. A routing-only
  # domain (the `~` prefix contributes no search suffix) sends thecluster.lan
  # to the global scope alone. Every other name goes to the global scope and
  # each default-route link in parallel, and the first answer wins.
  services.resolved.settings.Resolve.Domains = [ "~thecluster.lan" ];

  # `40-<interface>` is the unit NixOS generates for `networking.interfaces`
  # under networkd, so this merges into it. Public lookups that the gateway
  # answers first bypass pihole blocking.
  systemd.network.networks = lib.mkIf (gateway != null && gateway.interface != null) {
    "40-${gateway.interface}" = {
      dns = [ gateway.address ];
      networkConfig.DNSDefaultRoute = true;
    };
  };
}
