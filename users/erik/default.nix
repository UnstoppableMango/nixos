{ inputs, ... }:
let
  inherit (inputs) dotfiles;

  home =
    { pkgs, ... }:
    {
      imports = with dotfiles.modules.homeManager; [
        ai
        brave
        emacs
        erik
        ghostty
        gnome
        kitty
        vscode
        zed
      ];

      ai.enable = true;

      home.packages = with pkgs; [
        github-desktop
        seabird
        webex
      ];

      programs.lutris.enable = true;

      programs.git.signing = {
        format = "openpgp";
        key = "264283BBFDC491BC";
        signByDefault = true;
      };
    };

  nixos = {
    nixpkgs.overlays = [
      dotfiles.overlays.default
    ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "bak";

      users.erik = {
        imports = [ home ];
      };
    };
  };
in
{
  flake.homeModules.erik = home;
  flake.modules.homeManager.erik = home;

  flake.nixosModules.erik = nixos;
  flake.modules.nixos.erik = nixos;
}
