let
  nix = {
    # Don't kill my PC when building big things
    nix.daemonCPUSchedPolicy = "idle";
    nix.daemonIOSchedClass = "idle";
    nix.daemonIOSchedPriority = 7;
  };
in
{
  flake.nixosModules = { inherit nix; };
  flake.modules.nixos = { inherit nix; };
}
