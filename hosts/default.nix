{ inputs, self, ... }:
{
  imports = [
    ./hades
  ];

  flake.nixosConfigurations = {
    agreus = import ./agreus {
      inherit (self.modules.nixos) gnome;
      inherit (inputs.nixpkgs.lib) nixosSystem;
      inherit (inputs.disko.nixosModules) disko;
      inherit (inputs.home-manager.nixosModules) home-manager;
      inherit (inputs.sops-nix.nixosModules) sops;
    };

    # hades = import ./hades {
    #   inherit (self.modules.nixos) erik gnome hades ssh nixDaemonConfig;
    #   inherit (inputs.nixpkgs.lib) nixosSystem;
    #   inherit (inputs)
    #     disko
    #     home-manager
    #     sops-nix
    #     ;
    # };

    # pik8s1 = import ./pik8s1;
  };
}
