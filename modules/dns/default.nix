# Only 10.0.69.201 and .202 carry thecluster.lan; the pfSense gateways answer
# NXDOMAIN for it. Both front the in-cluster piholes, so each gateway is a
# second resolver for public names only (the-cluster#4458). See NETWORK.md,
# "DNS and service addressing".
{ config, lib, ... }:
let
  gateway = config.networking.defaultGateway;
in
{
  networking.nameservers = [
    "10.0.69.201"
    "10.0.69.202"
  ];

  # The routing-only domain sends thecluster.lan to the global scope alone.
  # Other names go to every scope in parallel, and the first answer wins.
  services.resolved.settings.Resolve.Domains = [ "~thecluster.lan" ];

  # Merges into NixOS's generated networkd unit. Public lookups the gateway
  # answers first bypass pihole blocking.
  systemd.network.networks = lib.mkIf (gateway != null && gateway.interface != null) {
    "40-${gateway.interface}" = {
      dns = [ gateway.address ];
      networkConfig.DNSDefaultRoute = true;
    };
  };
}
