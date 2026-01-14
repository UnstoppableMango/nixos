{ self, ... }:
{
  flake.clan =
    let
      ips = {
        agreus = "192.168.1.237";
        castor = "192.168.1.13";
        gaea = "192.168.1.11";
        hades = "192.168.1.69";
        pik8s1 = "192.168.1.101";
        pik8s2 = "192.168.1.102";
        pik8s3 = "192.168.1.103";
        pik8s4 = "192.168.1.104";
        pik8s5 = "192.168.1.105";
        pik8s6 = "192.168.1.106";
        pollux = "192.168.1.14";
        vrbox = "192.168.1.175";
        zeus = "192.168.1.10";
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

        vrbox = {
          deploy.targetHost = "root@${ips.vrbox}";
          tags = [ ];
        };
      };

      inventory.instances = {
        admin.roles.default = {
          tags.all = { };
          settings = {
            allowedKeys = {
              "root" =
                "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEwW6dUPKvKXXzj+gKJS7EXh6UzyLjzatrcPXa0Y2qvz erik@hades";
            };
          };
        };

        erik = {
          module.name = "users";
          roles.default = {
            tags.all = { };
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

            # extraModules = [ self.modules.nixos.erik ];
          };
        };
      };

      machines = {
        agreus =
          { ... }:
          {
            imports = [ self.modules.nixos.agreus ];

            # Enable remote Clan commands over SSH
            nixpkgs.hostPlatform = "x86_64-linux";

            clan.core.networking.targetHost = "root@${ips.agreus}";
          };

        vrbox =
          { ... }:
          {
            imports = [ self.modules.nixos.vrbox ];

            # Enable remote Clan commands over SSH
            nixpkgs.hostPlatform = "x86_64-linux";

            clan.core.networking.targetHost = "root@${ips.vrbox}";
          };
      };
    };
}
