{ inputs, self, ... }:
{
  flake.homeModules = self.modules.homeManager.erik;
  flake.modules.homeManager.erik =
    { pkgs, ... }:
    {
      imports = with inputs.dotfiles.modules.homeManager; [
        brave
        emacs
        erik
        ghostty
        gnome
        kitty
        vscode
        zed
      ];

      home.packages = with pkgs; [
        github-desktop
        seabird
      ];

      programs.lutris.enable = true;

      programs.git.signing = {
        format = "openpgp";
        key = "264283BBFDC491BC";
        signByDefault = true;
      };
    };

  flake.nixosModules.erik = self.modules.nixos.erik;
  flake.modules.nixos.erik = {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "bak";

      users.erik = {
        imports = [
          inputs.nixvim.homeModules.nixvim
          self.modules.homeManager.erik
        ];
      };
    };
  };
}
