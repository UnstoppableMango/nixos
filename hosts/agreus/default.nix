{
  disko,
  gnome,
  home-manager,
  sops-nix,
  nixosSystem,
}:
nixosSystem {
  system = "x86_64-linux";
  modules = [
    {
      imports = [
        disko.nixosModules.disko
        home-manager.nixosModules.home-manager
        sops-nix.nixosModules.sops
        # self.modules.nixos.erik
        gnome
        ./configuration.nix
        { hardware.facter.reportPath = ./facter.json; }
      ];
    }
  ];
}
