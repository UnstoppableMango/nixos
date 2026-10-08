# containerd pulls through Harbor's proxy-cache projects in the-cluster
# (apps/harbor-system/proxy-cache), falling back to the upstream registry.
#
# Each upstream host gets a hosts.toml whose only mirror is Harbor's project
# for it. `override_path` is what makes that work: containerd appends the
# repository to the host URL as given, so docker.io/library/nginx becomes
# harbor.thecluster.lan/v2/dockerhub/library/nginx rather than a path Harbor
# does not serve. Only pull and resolve go to the mirror; a push still goes
# upstream.
#
# The fallback is the failover plan. containerd tries the mirror, and on any
# error, an unreachable gateway, a Harbor 5xx, or a thecluster.lan lookup
# failing because pihole is down, retries against `server`. Harbor's own
# images and pihole's come back that way after a cold start, before either
# is serving. the-cluster's docs/harbor.md has the runbook.
#
# Harbor serves through the Gateway's *.thecluster.lan certificate, which
# chains to the UnMango Authority root. containerd verifies against the system
# bundle plus `ca`, so the root is named here rather than trusted system-wide.
{ lib, pkgs, ... }:
let
  harbor = "https://harbor.thecluster.lan/v2";
  ca = ../../certs/unmango-authority.crt;

  # Upstream host -> its registry API endpoint and Harbor project. The project
  # names are the keys of CACHES in the-cluster's proxy-cache.py.
  mirrors = {
    "docker.io" = {
      server = "https://registry-1.docker.io";
      project = "dockerhub";
    };
    "ghcr.io" = {
      server = "https://ghcr.io";
      project = "ghcr";
    };
    "quay.io" = {
      server = "https://quay.io";
      project = "quay";
    };
    "registry.k8s.io" = {
      server = "https://registry.k8s.io";
      project = "k8s";
    };
  };

  hostsToml =
    { server, project }:
    (pkgs.formats.toml { }).generate "hosts.toml" {
      inherit server;
      host."${harbor}/${project}" = {
        capabilities = [
          "pull"
          "resolve"
        ];
        override_path = true;
        ca = "${ca}";
      };
    };
in
{
  virtualisation.containerd.settings.plugins."io.containerd.grpc.v1.cri".registry.config_path =
    "/etc/containerd/certs.d";

  environment.etc = lib.mapAttrs' (
    host: mirror:
    lib.nameValuePair "containerd/certs.d/${host}/hosts.toml" { source = hostsToml mirror; }
  ) mirrors;
}
