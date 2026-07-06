{ inputs }:
{
  meta = {
    name = "thecluster";
    domain = "thecluster.io";
    description = "THECLUSTER";
  };

  modules."@UnstoppableMango/k3s" = import ./modules/service/k3s;
  modules."@UnstoppableMango/pi" = import ./modules/service/pi;
  modules."@UnstoppableMango/rosequartz" = import ./modules/service/rosequartz {
    fluxFor = system: inputs.a2b.legacyPackages.${system}.lib.flux;
  };
  modules."@UnstoppableMango/trouble" = import ./modules/service/trouble;

  inventory.machines =
    let
      piTags = [
        "basement"
        "pi4b"
        "k8s"
        "control-plane"
        "server"
        "headless"
      ];

      pik8s = idx: {
        deploy.targetHost = "root@192.168.1.10${toString idx}";
        tags = piTags;
      };
    in
    {
      # hades = {
      #   deploy.targetHost = "root@192.168.1.69";
      #   tags = [
      #     "workstation"
      #     "gaming"
      #     "tower"
      #   ];
      # };

      agreus = {
        deploy.targetHost = "root@10.0.69.187";
        tags = [
          "office"
          "k8s"
          "worker"
          "mini"
          "server"
          "rosequartz"
        ];
      };

      # castor = {
      #   deploy.targetHost = "root@192.168.1.13";
      #   tags = [
      #     "basement"
      #     "k8s"
      #     "worker"
      #     "rack"
      #     "server"
      #     "headless"
      #   ];
      # };

      # pollux = {
      #   deploy.targetHost = "root@192.168.1.14";
      #   tags = [
      #     "basement"
      #     "k8s"
      #     "worker"
      #     "rack"
      #     "server"
      #     "headless"
      #   ];
      # };

      # gaea = {
      #   deploy.targetHost = "root@192.168.1.11";
      #   tags = [
      #     "basement"
      #     "k8s"
      #     "worker"
      #     "rack"
      #     "server"
      #   ];
      # };

      # zeus = {
      #   deploy.targetHost = "root@192.168.1.10";
      #   tags = [
      #     "basement"
      #     "k8s"
      #     "worker"
      #     "tower"
      #     "server"
      #   ];
      # };

      pik8s1 = pik8s 1;
      pik8s2 = pik8s 2;
      pik8s3 = pik8s 3;

      pik8s4 = {
        deploy.targetHost = "root@10.0.69.104";
        tags = piTags ++ [ "rosequartz" ];
      };

      pik8s5 = {
        deploy.targetHost = "root@10.0.69.105";
        tags = piTags ++ [ "rosequartz" ];
      };

      pik8s6 = {
        deploy.targetHost = "root@10.0.69.106";
        tags = piTags ++ [ "rosequartz" ];
      };
    };

  inventory.instances = {
    erik = {
      module.name = "users";

      roles.default = {
        # Add to all machines
        tags.all = { };

        settings = {
          user = "erik";
          groups = [
            "wheel" # sudo
            "networkmanager"
            "video"
            "input"
          ];
        };

        # WIP
        # extraModules = with inputs; [
        #   home-manager.nixosModules.home-manager
        #   dotfiles.nixosModules.erik
        #   ./modules/users/erik
        # ];
      };
    };

    sshd = {
      module.name = "sshd";
      module.input = "clan-core";
      roles.server.tags.server = { };
      # roles.client.tags = [ "workstation" ];
    };

    raspberry-pi = {
      module.name = "@UnstoppableMango/pi";
      module.input = "self";
      roles.pi4b.tags.pi4b = { };
    };

    trouble = {
      module.name = "@UnstoppableMango/trouble";
      module.input = "self";

      roles.server.tags.server = { };
    };

    rosequartz = {
      module.name = "@UnstoppableMango/rosequartz";
      module.input = "self";

      roles.control-plane = {
        settings = {
          vip = "10.0.69.100";
          clusterName = "rosequartz";
        };

        machines.pik8s4.settings.ip = "10.0.69.104";
        machines.pik8s5.settings.ip = "10.0.69.105";
        machines.pik8s6.settings.ip = "10.0.69.106";
      };

      roles.worker = {
        machines.agreus.settings.ip = "10.0.69.187";
      };
    };
  };

  machines =
    let
      pik8s = idx: {
        users.users.root.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEwW6dUPKvKXXzj+gKJS7EXh6UzyLjzatrcPXa0Y2qvz erik@hades"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDB02UwohkEJGpb8Uud4bNQa73X9WvwQcbsRr1M8c7nztbnUCCeLBTyCtRTMnR6dmoQ3xfGLbv55nlTFT/s6ZZKWEAql/gPJoBF9nEr0622IJQ6VPIpgcI8eA2YDwYA0l19Bji4u3VbTMB+M3Tz7JRmKqHo5bUvnZWi2cp+G5Hh2f2k0lQOa9ttjvVlLBQLCJV8NmCxikJS0ZuH2+KJPT2DVsY8dMZ2fQHh1/DI+ZAo6V1qjEU4SQKjpdIrUsPt9Ah1CBU7W3tG57+aYCoaay/BuUY4zlewxGdn3MAv/mjyqF6WgkzCilr7VBnO8CUgzLGu6F+8ljEJVZ5zqyTGfuni/069qMROEp6abhQe7MGToqFgsDkIJhSihomUNylM2piVFobZTeqGBXqh8h3W1fkQHsfMjYbkYP6kHx7yZ03Xw7X+4ZfySZ4s1PqvJE1ZALHdpzYSDK06+iqbJ3ZA/lpipg+Mzx7iRrD3CsPjzgi1iE6w5DVu5xAMIZIRFetTIAs= erik@darter"
        ];
      };
    in
    {
      agreus = {
        imports = [ ./machines/agreus/configuration.nix ];
        users.users.root.openssh.authorizedKeys.keys = [
          "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEwW6dUPKvKXXzj+gKJS7EXh6UzyLjzatrcPXa0Y2qvz erik@hades"
          "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDB02UwohkEJGpb8Uud4bNQa73X9WvwQcbsRr1M8c7nztbnUCCeLBTyCtRTMnR6dmoQ3xfGLbv55nlTFT/s6ZZKWEAql/gPJoBF9nEr0622IJQ6VPIpgcI8eA2YDwYA0l19Bji4u3VbTMB+M3Tz7JRmKqHo5bUvnZWi2cp+G5Hh2f2k0lQOa9ttjvVlLBQLCJV8NmCxikJS0ZuH2+KJPT2DVsY8dMZ2fQHh1/DI+ZAo6V1qjEU4SQKjpdIrUsPt9Ah1CBU7W3tG57+aYCoaay/BuUY4zlewxGdn3MAv/mjyqF6WgkzCilr7VBnO8CUgzLGu6F+8ljEJVZ5zqyTGfuni/069qMROEp6abhQe7MGToqFgsDkIJhSihomUNylM2piVFobZTeqGBXqh8h3W1fkQHsfMjYbkYP6kHx7yZ03Xw7X+4ZfySZ4s1PqvJE1ZALHdpzYSDK06+iqbJ3ZA/lpipg+Mzx7iRrD3CsPjzgi1iE6w5DVu5xAMIZIRFetTIAs= erik@darter"
        ];
      };

      pik8s1 = pik8s 1;
      pik8s2 = pik8s 2;
      pik8s3 = pik8s 3;
      pik8s4 = pik8s 4;
      pik8s5 = pik8s 5;
      pik8s6 = pik8s 6;
    };
}
