# The resolvers every machine in the clan uses.
#
# 10.0.69.201 and 10.0.69.202 are the only resolvers on the network that carry
# the `thecluster.lan` zone. The pfSense gateways (192.168.1.1 on VLAN 1,
# 10.0.69.1 on VLAN 20) answer NXDOMAIN for names in it, so a machine pointed
# at its gateway cannot resolve the `ncps.thecluster.lan` substituter in
# ../cache and silently falls through to the public caches instead.
#
# Both are full recursors and serve public names too, so this pair is the
# complete list rather than an internal-only prefix. They sit on VLAN 20,
# on-link for every machine there and reachable over enp7s0 from hades.
{
  networking.nameservers = [
    "10.0.69.201"
    "10.0.69.202"
  ];

  # Every machine runs systemd-resolved, so the pair above lands in the global
  # scope and anything a link supplies of its own is scoped to that link. Only
  # hades has such a link today: NetworkManager on wlp5s0, the wireless
  # fallback behind the two wired interfaces, whose DHCP lease carries public
  # resolvers that know nothing about thecluster.lan.
  #
  # A routing-only domain (the `~` prefix contributes no search suffix) sends
  # thecluster.lan to the global scope explicitly, instead of leaving the
  # choice of scope to resolved while the fallback is associated.
  services.resolved.domains = [ "~thecluster.lan" ];
}
