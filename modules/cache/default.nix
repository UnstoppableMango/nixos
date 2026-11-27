# The `trusted-nix-caches` service only permits caches, so nix-community is
# listed here too for the daemon to pull from it.
{ address, pubkey }:
let
  attic = import ../attic/net.nix;
in
{
  nix.settings = {
    extra-substituters = [
      "http://${address}:${toString attic.port}/${attic.cache}"
      "https://nix-community.cachix.org"
    ];
    extra-trusted-public-keys = [ pubkey ];
    fallback = true;
    # Keeps a down attic from stalling every substituter miss.
    connect-timeout = 5;
  };
}
