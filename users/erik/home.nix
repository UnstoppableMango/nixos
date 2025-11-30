{ pkgs, ... }:
{
  home.packages = with pkgs; [
    github-desktop
    seabird
  ];

  programs.lutris.enable = true;

  programs.git = {
    signing = {
      format = "openpgp";
      key = "264283BBFDC491BC";
      signByDefault = true;
    };
  };
}
