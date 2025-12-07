{
  flake = {
    modules.nixos.ssh = ./ssh.nix;
    nixosModules.ssh = ./ssh.nix;
  };
}
