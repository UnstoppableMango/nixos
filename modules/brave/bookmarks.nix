# Chromium `ManagedBookmarks` policy value, shared by ./default.nix (which
# installs it on hades) and flake.nix's `brave-bookmarks-policy` package (which
# renders the same JSON for hosts outside this clan).
#
# https://chromeenterprise.google/policies/#ManagedBookmarks
[
  { toplevel_name = "thecluster"; }
  {
    name = "Headlamp";
    url = "https://headlamp.thecluster.lan";
  }
  {
    name = "Ceph";
    url = "https://ceph.thecluster.lan";
  }
  {
    name = "Harbor";
    url = "https://harbor.thecluster.lan";
  }
  {
    name = "Gitea";
    url = "https://gitea.thecluster.lan";
  }
  {
    name = "Prometheus";
    url = "https://prom.thecluster.io";
  }
  {
    name = "Dex";
    url = "https://dex.thecluster.io";
  }
  {
    name = "apps";
    children = [
      {
        name = "Plex";
        url = "https://plex.thecluster.lan";
      }
      {
        name = "qBittorrent";
        url = "https://qbittorrent.thecluster.lan";
      }
      {
        name = "Deluge";
        url = "https://deluge.thecluster.lan";
      }
      {
        name = "Copyparty";
        url = "https://copyparty.thecluster.lan";
      }
      {
        name = "Tubesync";
        url = "https://tubesync.thecluster.lan";
      }
      {
        name = "Bitwarden";
        url = "https://bitwarden.thecluster.io";
      }
    ];
  }
]
