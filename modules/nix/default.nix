# Nix daemon settings shared by every machine. Substituters live in ../cache.
{
  # `extra-` so this adds to clan-core's nix-command and flakes.
  nix.settings.extra-experimental-features = [ "pipe-operators" ];
}
