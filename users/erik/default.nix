{ inputs, ... }:
{
  flake.modules.nixos.erik = pkgs: {
    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "bak";

      users.erik = {
        imports = with inputs.dotfiles.homeModules; [
          inputs.nixvim.homeModules.nixvim
          erik
          gnome
          vscode
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
        ];
      };
    };
  };
}
