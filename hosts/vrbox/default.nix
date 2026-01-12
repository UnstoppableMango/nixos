let
  host = "vrbox";
in
{
  flake = {
    modules.nixos.${host} = ./configuration.nix;
    nixosModules.${host} = ./configuration.nix;
  };
}
