# The `trusted-nix-caches` service only permits caches, so nix-community is
# listed here too for the daemon to pull from it.
{
  nix.settings = {
    extra-substituters = [
      "https://ncps.thecluster.lan"
      "https://mangopkgs.cachix.org"
      "https://nix-community.cachix.org"
      # On every machine, since a Pi's closure may be built elsewhere.
      "https://nixos-raspberrypi.cachix.org"
      "https://unmango.cachix.org"
      "https://unstoppablemango.cachix.org"
    ];

    extra-trusted-public-keys = [
      # Read from https://ncps.thecluster.lan/pubkey: a superseded key is
      # well-formed and silently ignores every substitute.
      "ncps.thecluster.lan:pAJGNVSRmG7gCDSOAaiHDxLFUSdys5Pk0XvcJ5803Dw="
      "mangopkgs.cachix.org-1:uJ5FgSbOg1uiXLcL0gBh1lO+y3KVuthy6UeOFYR1fLk="
      "nixos-raspberrypi.cachix.org-1:4iMO9LXa8BqhU+Rpg6LQKiGa2lsNh/j2oiYLNOQ5sPI="
      "unmango.cachix.org-1:Psb+0nALJfIcYiZLc9JYri4FJGNnzM6goZX7iLErXCI="
      "unstoppablemango.cachix.org-1:m7uEI6X1Ov8DyFWJQX4WsRFRWFuzRW5c/Xms8ZaP74U="
    ];
  };
}
