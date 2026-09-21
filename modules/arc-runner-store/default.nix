# The nix store the rosequartz GitHub Actions runner pods share on this node.
#
# The pods mount this directory at /nix, so it holds every store path they
# realise and nix's build directory, and it outlives any one pod: a second pod
# on the same node finds the closure already there instead of refetching it
# from ncps.
#
# It is deliberately not /nix. That is the booted system's store, owned by root
# and shared with nothing.
#
# Declaring the directory here is what lets the runner pods drop their
# privileged init container: kubelet creates a hostPath as root, and nothing in
# the pod can chown it without one.
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
      # nix removes a build directory when the build ends, but a nix killed
      # with its pod leaves one behind, and the garbage collector walks the
      # store rather than this path. `e` adjusts and cleans an existing
      # directory without creating one.
      "e ${cfg.path}/var/nix/builds - - - ${cfg.buildsMaxAge}"
    ];
  };
}
