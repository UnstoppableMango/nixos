{ pkgs ? import <nixpkgs> { } }:

pkgs.mkShell {
  name = "UnstoppableMangoNixOS";
  buildInputs = with pkgs; [
    nixFlakes
  ];

  shellHook = ''
    echo "Welcome to UnstoppableMango's shell";
  '';
}
