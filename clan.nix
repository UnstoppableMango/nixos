{
  meta = {
    name = "thecluster";
    domain = "thecluster.io";
    description = "THECLUSTER";
  };

  inventory.machines =
    let
      pik8s = idx: {
        deploy.targetHost = "root@192.168.1.10${toString idx}";
        tags = [
          "basement"
          "pi"
          "k8s"
          "control-plane"
          "rack"
        ];
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
        deploy.targetHost = "root@192.168.1.237";
        tags = [
          "office"
          "k8s"
          "worker"
          "mini"
        ];
      };

      castor = {
        deploy.targetHost = "root@192.168.1.13";
        tags = [
          "basement"
          "k8s"
          "worker"
          "rack"
        ];
      };

      pollux = {
        deploy.targetHost = "root@192.168.1.14";
        tags = [
          "basement"
          "k8s"
          "worker"
          "rack"
        ];
      };

      gaea = {
        deploy.targetHost = "root@192.168.1.11";
        tags = [
          "basement"
          "k8s"
          "worker"
          "rack"
        ];
      };

      zeus = {
        deploy.targetHost = "root@192.168.1.10";
        tags = [
          "basement"
          "k8s"
          "worker"
          "tower"
        ];
      };

      pik8s1 = pik8s 1;
      pik8s2 = pik8s 2;
      pik8s3 = pik8s 3;
      pik8s4 = pik8s 4;
      pik8s5 = pik8s 5;
      pik8s6 = pik8s 6;
    };

  inventory.instances = {
    admin = {
      roles.default.tags.all = { };

      roles.default.settings = {
        allowedKeys = {
          "root" =
            "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEwW6dUPKvKXXzj+gKJS7EXh6UzyLjzatrcPXa0Y2qvz erik@hades";
        };
      };
    };

    erik = {
      module.name = "users";

      # Add to all machines
      roles.default.tags.all = { };

      roles.default.settings = {
        user = "erik";
        groups = [
          "wheel" # sudo
          "networkmanager"
          "video"
          "input"
        ];
      };
    };
  };

  machines = {
    agreus = {
      imports = [ ./machines/agreus/configuration.nix ];
      users.users.root.openssh.authorizedKeys.keys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEwW6dUPKvKXXzj+gKJS7EXh6UzyLjzatrcPXa0Y2qvz erik@hades"
        "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDB02UwohkEJGpb8Uud4bNQa73X9WvwQcbsRr1M8c7nztbnUCCeLBTyCtRTMnR6dmoQ3xfGLbv55nlTFT/s6ZZKWEAql/gPJoBF9nEr0622IJQ6VPIpgcI8eA2YDwYA0l19Bji4u3VbTMB+M3Tz7JRmKqHo5bUvnZWi2cp+G5Hh2f2k0lQOa9ttjvVlLBQLCJV8NmCxikJS0ZuH2+KJPT2DVsY8dMZ2fQHh1/DI+ZAo6V1qjEU4SQKjpdIrUsPt9Ah1CBU7W3tG57+aYCoaay/BuUY4zlewxGdn3MAv/mjyqF6WgkzCilr7VBnO8CUgzLGu6F+8ljEJVZ5zqyTGfuni/069qMROEp6abhQe7MGToqFgsDkIJhSihomUNylM2piVFobZTeqGBXqh8h3W1fkQHsfMjYbkYP6kHx7yZ03Xw7X+4ZfySZ4s1PqvJE1ZALHdpzYSDK06+iqbJ3ZA/lpipg+Mzx7iRrD3CsPjzgi1iE6w5DVu5xAMIZIRFetTIAs= erik@darter"
      ];
    };
  };
}
