{
  disko,
  erik,
  gnome,
  hades,
  ssh,
  nixDaemonConfig,
  nixos-hardware,
  home-manager,
  nixosSystem,
  sops-nix,
  ...
}:
nixosSystem {
  modules = [
    nixos-hardware.nixosModules.asus-rog-strix-x570e
    nixos-hardware.nixosModules.common-pc-ssd
    home-manager.nixosModules.home-manager
    disko.nixosModules.disko
    sops-nix.nixosModules.sops
    erik
    gnome
    hades
    ssh
    nixDaemonConfig
  ];
}
