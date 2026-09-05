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
  networking = {
    nameservers = [
      "10.0.69.201"
      "10.0.69.202"
    ];

    # hades is the only machine on resolvconf: it opts out of clan-core's
    # recommended defaults in clan.nix, so it does not get systemd-resolved
    # like the rest of the clan, and it is also the only machine with a second
    # source of resolvers (NetworkManager, from wlp5s0's DHCP lease, where the
    # wired link is primary and wireless is the fallback).
    #
    # openresolv keeps one record per source and orders anything it does not
    # find in interface_order alphabetically, which puts `NetworkManager` ahead
    # of `static`, the record NixOS writes for the nameservers above. glibc
    # treats the first NXDOMAIN it gets as final rather than trying the next
    # server, so the DHCP resolvers alone decide whether an internal name
    # resolves. Naming `static` pins the pair to the front; the DHCP resolvers
    # stay in resolv.conf and take over once these two time out.
    #
    # Inert on the systemd-resolved machines, which do not generate this file.
    resolvconf.extraConfig = ''
      interface_order='lo lo[0-9]* static'
    '';
  };
}
