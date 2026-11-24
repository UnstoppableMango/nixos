# Store garbage collection through `nh clean`, which keeps the newest
# generations even past `--keep-since`, unlike `nix.gc`.
# The hercules-ci-agent service stops its agents while this runs.
{ lib, ... }:
{
  programs.nh = {
    enable = true;
    clean = {
      enable = lib.mkDefault true;
      dates = "weekly";
      extraArgs = "--keep-since 14d --keep 5";
    };
  };
}
