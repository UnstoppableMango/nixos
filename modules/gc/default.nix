# Periodic store garbage collection, through `nh clean`.
#
# nh keeps the newest generations of each profile even when they are older than
# `--keep-since`, so a machine that has not been redeployed in a while still has
# something to roll back to. Plain `nix.gc --delete-older-than` would not.
#
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
