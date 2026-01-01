{ inputs, self, ... }:
{
  flake.nixosConfigurations."agreus" = inputs.nixpkgs.lib.nixosSystem {
    system = "x86_64-linux";

    modules = with inputs; [
      disko.nixosModules.disko
      home-manager.nixosModules.home-manager
      {
        home-manager.users.erik.imports = [
          nixvim.homeModules.nixvim
          dotfiles.modules.homeManager.erik
        ];
      }
      self.modules.nixos.gnome
      ./configuration.nix
      { hardware.facter.reportPath = ./facter.json; }
    ];
  };
}
