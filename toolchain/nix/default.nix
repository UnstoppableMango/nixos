let
  nixDaemonConfig = {
    # Don't kill my PC when building big things
    daemonCPUSchedPolicy = "idle";
    daemonIOSchedClass = "idle";
    daemonIOSchedPriority = 7;
  };
in
{
  flake.nixosModules = { nix = nixDaemonConfig; };
  flake.modules.nixos = { nix = nixDaemonConfig; };
}
