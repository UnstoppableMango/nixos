{
  disko,
  gnome,
  home-manager,
  sops,
  nixosSystem,
}:
nixosSystem {
  system = "x86_64-linux";
  modules = [
    {
      imports = [
        disko
        home-manager
        sops
        gnome
        ./configuration.nix
        { hardware.facter.reportPath = ./facter.json; }
      ];
    }
  ];
}
