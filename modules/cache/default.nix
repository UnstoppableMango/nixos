# Nix substituters every machine in the clan uses.
#
# Attached to all machines through the `clan-cache` instance in clan.nix, whose
# `trusted-nix-caches` service supplies the trusted-substituters and
# trusted-public-keys entries for cache.clan.lol and nix-community.cachix.org.
# That service only marks those caches as *permitted*, so nix-community is
# listed here as well to make the daemon actually pull from it.
#
# Machine-specific caches stay in the machine's own `nix.settings`.
#
# experimental-features is not set here: clan-core's clanCore/nix-settings.nix
# already enables nix-command and flakes on every machine in the clan.
{
  nix.settings = {
    extra-substituters = [
      "https://ncps.thecluster.lan"
      "https://mangopkgs.cachix.org"
      "https://nix-community.cachix.org"
      "https://unmango.cachix.org"
      "https://unstoppablemango.cachix.org"
    ];

    extra-trusted-public-keys = [
      "ncps.thecluster.lan:D8fcKW2/D+zjKOABa3bDjEe8x+EPZpXnBDm+XwtNrhI="
      "mangopkgs.cachix.org-1:uJ5FgSbOg1uiXLcL0gBh1lO+y3KVuthy6UeOFYR1fLk="
      "unmango.cachix.org-1:Psb+0nALJfIcYiZLc9JYri4FJGNnzM6goZX7iLErXCI="
      "unstoppablemango.cachix.org-1:m7uEI6X1Ov8DyFWJQX4WsRFRWFuzRW5c/Xms8ZaP74U="
    ];
  };
}
