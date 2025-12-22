let
  nixDaemonConfig = {
    nix = {
      # Don't kill my PC when building big things
      daemonCPUSchedPolicy = "idle";
      daemonIOSchedClass = "idle";
      daemonIOSchedPriority = 7;
    };
  };
in
{
  flake.nixosModules = { inherit nixDaemonConfig; };
  flake.modules.nixos = { inherit nixDaemonConfig; };
}
