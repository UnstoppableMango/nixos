{ inputs, pkgs, ... }:
{
  home-manager = {
    useGlobalPkgs = true;
    useUserPackages = true;
    backupFileExtension = "bak";
    extraSpecialArgs = { inherit inputs; };

    users.erik = {
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

      dotfiles = {
        ai.enable = true;
        openshift.enable = true;
        brave.enable = true;
        emacs.enable = true;
        ghostty.enable = true;
        gnome.enable = true;
        kitty.enable = true;
        vscode.enable = true;
        zed.enable = true;
      };
    };
  };
}
