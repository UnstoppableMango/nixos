{ inputs, ... }:
{
  home-manager.useGlobalPkgs = true;
  home-manager.useUserPackages = true;
  home-manager.backupFileExtension = "bak";
  home-manager.users.erik = {
    imports = with inputs.dotfiles.homeModules; [
      inputs.nixvim.homeModules.nixvim
      erik
      gnome
      vscode
      ./home.nix
    ];
  };
}
