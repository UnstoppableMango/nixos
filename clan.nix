{ config, ... }:
{
  flake.clan =
    let
      ips = {
        agreus = "192.168.1.237";
      };
    in
    {
      meta = {
        name = "THECLUSTER";
        domain = "thecluster.lan";
        description = "Clan for THECLUSTER";
      };

      inventory.machines = {
        agreus = {
          deploy.targetHost = "root@${ips.agreus}";
          tags = [ ];
        };
      };

      inventory.instances = {
        erik = {
          module.name = "users";
          roles.default = {
            tags.all = {};
            settings = {
              user = "erik";
              groups = [
                "wheel"
                "networkmanager"
                "docker"
                "openrazer"
                "libvirt" # crc wants `libvirt` not `libvirtd`
              ];
            };

            extraModules = [ config.modules.nixos.erik ];
          };
        };
      };

      machines = {
        agreus =
          { config, ... }:
          {
            imports = [ config.modules.nixos.agreus ];

            # Enable remote Clan commands over SSH
            nixpkgs.hostPlatform = "x86_64-linux";

            clan.core.networking.targetHost = "root@${ips.agreus}";
          };
      };
    };
}
