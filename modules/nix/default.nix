# Nix daemon settings shared by every machine in the clan.
#
# Substituters live in ../cache, which the clan-cache instance attaches. This
# module is for settings that are not about where the daemon fetches from.
{
  # The `|>` and `<|` operators. `extra-` rather than a plain assignment so this
  # adds to nix-command and flakes, which clan-core's recommended defaults set
  # on every machine, instead of replacing them.
  nix.settings.extra-experimental-features = [ "pipe-operators" ];
}
