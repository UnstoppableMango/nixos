# The nix store the rosequartz runner pods share on this node, so a second pod
# finds its closure already there. Not /nix, the booted system's store.
# Declared here so the pods need no privileged init container to chown it.
{ config, lib, ... }:
let
  cfg = config.arcRunnerStore;
  inherit (lib)
    mkEnableOption
    mkIf
    mkOption
    types
    ;
in
{
  options.arcRunnerStore = {
    enable = mkEnableOption "a shared nix store for the ARC runner pods";

    path = mkOption {
      type = types.str;
      default = "/var/lib/arc-nix";
      description = "Directory the runner pods mount at /nix.";
    };

    uid = mkOption {
      type = types.ints.unsigned;
      default = 1001;
      description = ''
        Owner of the store. This is the `runner` user inside
        ghcr.io/unmango/actions-runner, not a user on this machine, so it is
        written numerically and no account is created for it. A store left
        owned by a different uid after an image bump has to be discarded
        rather than chowned.
      '';
    };

    gid = mkOption {
      type = types.ints.unsigned;
      default = 1001;
      description = "Group owner of the store, the runner group in the pod image.";
    };

    buildsMaxAge = mkOption {
      type = types.str;
      default = "7d";
      description = ''
        Age at which a leftover build directory is removed, in
        systemd.time(7) format.
      '';
    };
  };

  config = mkIf cfg.enable {
    systemd.tmpfiles.rules = [
      "d ${cfg.path} 0755 ${toString cfg.uid} ${toString cfg.gid} -"
      # A nix killed with its pod leaves its build directory, which GC never walks.
      # `e` cleans an existing directory without creating one.
      "e ${cfg.path}/var/nix/builds - - - ${cfg.buildsMaxAge}"
    ];
  };
}
