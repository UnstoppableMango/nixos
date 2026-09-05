{ inputs, ... }:
let
  inherit (inputs.hosts) hosts;

  # Trusted for root on every machine, via the clan `sshd` service.
  sshKeys = {
    hades = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEwW6dUPKvKXXzj+gKJS7EXh6UzyLjzatrcPXa0Y2qvz erik@hades";
    darter-rsa = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDB02UwohkEJGpb8Uud4bNQa73X9WvwQcbsRr1M8c7nztbnUCCeLBTyCtRTMnR6dmoQ3xfGLbv55nlTFT/s6ZZKWEAql/gPJoBF9nEr0622IJQ6VPIpgcI8eA2YDwYA0l19Bji4u3VbTMB+M3Tz7JRmKqHo5bUvnZWi2cp+G5Hh2f2k0lQOa9ttjvVlLBQLCJV8NmCxikJS0ZuH2+KJPT2DVsY8dMZ2fQHh1/DI+ZAo6V1qjEU4SQKjpdIrUsPt9Ah1CBU7W3tG57+aYCoaay/BuUY4zlewxGdn3MAv/mjyqF6WgkzCilr7VBnO8CUgzLGu6F+8ljEJVZ5zqyTGfuni/069qMROEp6abhQe7MGToqFgsDkIJhSihomUNylM2piVFobZTeqGBXqh8h3W1fkQHsfMjYbkYP6kHx7yZ03Xw7X+4ZfySZ4s1PqvJE1ZALHdpzYSDK06+iqbJ3ZA/lpipg+Mzx7iRrD3CsPjzgi1iE6w5DVu5xAMIZIRFetTIAs= erik@darter";
  };

  # erik also gets a couple of older darter keys that root does not.
  erikSshKeys = builtins.attrValues sshKeys ++ [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDRaJ8OwIVbSMTSzt4Z34lZghDvaT169OvzXXEldA9Rz06LH1/6VaKX1RsZaqMBtmfVlUATat9e53AOUbKORj7ZqZA19iOtV2uu/aXKyRWB+6sn0LFmMRIgnCyNInkSrbdwUBiJKyf1eiu5V5LgOGgfjteGOowF25olgFB5NzMujkHNzd/4X4Ehew3GjHN5x+swKlBQgi5ulGILaaTtiCrdVe/Di66CUpBGvtzi3SoUJ/nmLtvFFUb7osJzuiUYa5sQ1eLVtFzJ2La3bl/PAohJk5zBi/XQTmDrQK/yaHLr0U2z27CWOW8fHRcAHFXAcUCH8I4AeKPtFVxgC0hmvx6p2RBf++++FwWpedZG+P72HZsbh0oWHY54yLOpdE5siCqtiQ/lT6L8GUhw/uBZSnGOAfI12fcOsDgN0R0pow6zWQklgIKxgjgW5YL8iPCInL44slrBMCbdkmixfVcNZPhjNMbc+QaHTD7YmPbAvIvG4K8cJrf9xuw85E0qxLyjCSc= erik@darter"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMsFkHA8jLd9sHV5a/zcMsaxo/o+ZnEB95CBSRnu3YfD erik@darter"
  ];

  # Which machines this clan manages. Tags and addresses come from the `hosts`
  # flake, which covers the whole network, so narrow it to these names; comment
  # an entry out to drop the machine from the inventory.
  clanMachines = {
    hades = { };
    agreus = { };
    castor = { };
    gaea = { };
    pollux = { };
    zeus = { };
    pik8s1 = { };
    pik8s2 = { };
    pik8s3 = { };
    pik8s4 = { };
    pik8s5 = { };
    pik8s6 = { };
  };

  # intersectAttrs drops unmatched names silently, so a typo above would quietly
  # remove a machine from the clan rather than fail. Check first.
  unknown = builtins.attrNames (builtins.removeAttrs clanMachines (builtins.attrNames hosts));

  managed =
    if unknown == [ ] then
      builtins.intersectAttrs clanMachines hosts
    else
      throw "clan.nix: not in the hosts flake: ${builtins.concatStringsSep ", " unknown}";

  machines = builtins.mapAttrs (_: host: { inherit (host) tags; }) managed;

in
{
  meta = {
    name = "thecluster";
    domain = "thecluster.io";
    description = "THECLUSTER";
  };

  modules."@UnstoppableMango/harmonia" = import ./modules/service/harmonia;
  modules."@UnstoppableMango/k3s" = import ./modules/service/k3s;
  modules."@UnstoppableMango/pi" = import ./modules/service/pi;
  modules."@UnstoppableMango/trouble" = import ./modules/service/trouble;

  inventory.machines = machines;

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

          openssh.authorizedKeys.keys = erikSshKeys;
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

      # Every machine runs sshd with a CA-signed host cert for
      # <machine>.thecluster.io, and trusts that CA in return, so connecting
      # never falls back to TOFU.
      roles.server.tags.all = { };
      roles.server.settings.authorizedKeys = sshKeys;
      roles.client.tags.all = { };
    };

    clan-cache = {
      module.name = "trusted-nix-caches";
      module.input = "clan-core";

      roles.default = {
        # cache.clan.lol and nix-community.cachix.org, trusted everywhere.
        tags.all = { };

        # The service only marks caches as trusted. ./modules/cache carries the
        # substituters the daemon actually pulls from, shared by every machine.
        extraModules = [ ./modules/cache ];
      };
    };

    # Serves each server's own store to the clan. Complements ./modules/cache,
    # whose entries are all hosted or pull-through caches: nothing there offers
    # a path that only ever existed on one of these machines.
    harmonia = {
      module.name = "@UnstoppableMango/harmonia";
      module.input = "self";

      # Addresses come from the hosts flake rather than <machine>.thecluster.io,
      # so reaching a server does not depend on LAN DNS.
      roles.server.machines = {
        gaea.settings.address = managed.gaea.ip;
        hades.settings.address = managed.hades.ip;
        zeus.settings.address = managed.zeus.ip;
      };

      roles.client.tags.all = { };
    };

    internet = {
      module.name = "internet";
      module.input = "clan-core";
      roles.default.machines = builtins.mapAttrs (_: host: { settings.host = host.ip; }) managed;
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

    # THECLUSTER's vanilla-Kubernetes cluster, "rosequartz", is defined via
    # cairn's `cairn.clusters.rosequartz` option tree in flake.nix (spec at
    # ./clan/rosequartz-cluster.nix), which lowers to the per-service
    # `rosequartz-*` inventory instances that used to be hand-written here.
  };

  machines = {
    hades = {
      clan.core.deployment.requireExplicitUpdate = true;

      imports = with inputs; [
        nixos-hardware.nixosModules.asus-rog-strix-x570e
        nixos-hardware.nixosModules.common-pc-ssd
        home-manager.nixosModules.home-manager
        { nixpkgs.overlays = [ dotfiles.overlays.default ]; }
        ./machines/hades/configuration.nix
      ];
      # TODO: re-enable once we've reviewed the networkd/doc-stripping defaults
      clan.core.enableRecommendedDefaults = false;
    };

    agreus = {
      imports = [ ./machines/agreus/configuration.nix ];
    };
  };
}
