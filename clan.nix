{ inputs, ... }:
let
  inherit (inputs.hosts) hosts;

  sshKeys = import ./clan/ssh-keys.nix;

  # erik also gets a couple of older darter keys that root does not.
  erikSshKeys = builtins.attrValues sshKeys ++ [
    "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDRaJ8OwIVbSMTSzt4Z34lZghDvaT169OvzXXEldA9Rz06LH1/6VaKX1RsZaqMBtmfVlUATat9e53AOUbKORj7ZqZA19iOtV2uu/aXKyRWB+6sn0LFmMRIgnCyNInkSrbdwUBiJKyf1eiu5V5LgOGgfjteGOowF25olgFB5NzMujkHNzd/4X4Ehew3GjHN5x+swKlBQgi5ulGILaaTtiCrdVe/Di66CUpBGvtzi3SoUJ/nmLtvFFUb7osJzuiUYa5sQ1eLVtFzJ2La3bl/PAohJk5zBi/XQTmDrQK/yaHLr0U2z27CWOW8fHRcAHFXAcUCH8I4AeKPtFVxgC0hmvx6p2RBf++++FwWpedZG+P72HZsbh0oWHY54yLOpdE5siCqtiQ/lT6L8GUhw/uBZSnGOAfI12fcOsDgN0R0pow6zWQklgIKxgjgW5YL8iPCInL44slrBMCbdkmixfVcNZPhjNMbc+QaHTD7YmPbAvIvG4K8cJrf9xuw85E0qxLyjCSc= erik@darter"
    "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMsFkHA8jLd9sHV5a/zcMsaxo/o+ZnEB95CBSRnu3YfD erik@darter"
  ];

  # Tags and addresses come from the `hosts` flake. Comment an entry out to drop
  # the machine.
  clanMachines = {
    hades = { };
    agreus = { };
    apollo = { };
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
    pik8s7 = { };
    pik8s8 = { };
    pik8s9 = { };
  };

  # intersectAttrs drops unmatched names silently, so a typo would remove a machine.
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

  modules."@UnstoppableMango/base" = import ./modules/service/base;
  modules."@UnstoppableMango/build-host" = import ./modules/service/build-host;
  modules."@UnstoppableMango/harmonia" = import ./modules/service/harmonia;
  modules."@UnstoppableMango/hercules-ci-agent" =
    inputs.nixpkgs.lib.modules.importApply ./modules/service/hercules-ci-agent
      { inherit inputs; };
  modules."@UnstoppableMango/k3s" = import ./modules/service/k3s;
  modules."@UnstoppableMango/pi" = import ./modules/service/pi;
  modules."@UnstoppableMango/trouble" = import ./modules/service/trouble;

  inventory.machines = machines;

  inventory.instances = {
    # Attached here so a new machine inherits them by joining the inventory.
    base = {
      module.name = "@UnstoppableMango/base";
      module.input = "self";
      roles.default.tags.all = { };
      # By address, so pushes still land while DNS is down.
      roles.default.settings.uptimeUrl = "https://${managed.pik8s3.ip}:8443";
    };

    erik = {
      module.name = "users";

      roles.default = {
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

    tz = {
      module.name = "users";

      roles.default = {
        machines.hades = { };

        settings = {
          user = "tz";
          prompt = true;
          groups = [
            "networkmanager"
            "video"
            "input"
            "audio"
          ];
        };
      };
    };

    sshd = {
      module.name = "sshd";
      module.input = "clan-core";

      # CA-signed host certs, so connecting never falls back to TOFU.
      roles.server.tags.all = { };
      roles.server.settings.authorizedKeys = sshKeys;
      roles.client.tags.all = { };
    };

    # The Pis build on gaea: a Pi can only substitute from caches it already
    # trusts, and compiles everything else itself.
    build-host = {
      module.name = "@UnstoppableMango/build-host";
      module.input = "self";
      roles.builder.machines.gaea.settings.address = managed.gaea.ip;
      roles.client.machines = builtins.mapAttrs (_: host: { settings.address = host.ip; }) (
        inputs.nixpkgs.lib.filterAttrs (_: host: builtins.elem "pi4b" host.tags) managed
      );
    };

    clan-cache = {
      module.name = "trusted-nix-caches";
      module.input = "clan-core";

      roles.default = {
        tags.all = { };

        # This only marks caches trusted; ./modules/cache sets the substituters.
        extraModules = [ ./modules/cache ];
      };
    };

    # Serves each server's store, which no hosted cache in ./modules/cache offers.
    harmonia = {
      module.name = "@UnstoppableMango/harmonia";
      module.input = "self";

      # By address, so reaching a server does not depend on LAN DNS.
      # A server must stay up: the Hercules agents fail their startup check when a
      # substituter is unreachable.
      roles.server.machines = {
        apollo.settings.address = managed.apollo.ip;
        gaea.settings.address = managed.gaea.ip;
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

    # rosequartz is defined through cairn's `cairn.clusters.rosequartz` in flake.nix,
    # from ./clan/rosequartz-cluster.nix.
  };

  machines = {
    hades = {
      clan.core.deployment.requireExplicitUpdate = true;

      # The default root@hades.thecluster.io does not resolve.
      clan.core.networking.targetHost = "root@${managed.hades.ip}";

      imports = with inputs; [
        nixos-hardware.nixosModules.asus-rog-strix-x570e
        nixos-hardware.nixosModules.common-pc-ssd
        # erik's home is a standalone Home Manager install, so only the overlay is taken.
        { nixpkgs.overlays = [ dotfiles.overlays.default ]; }
        ./machines/hades/configuration.nix
      ];
    };

    agreus = {
      imports = [ ./machines/agreus/configuration.nix ];
    };

    # For the attic and builder VMs (modules/attic, modules/builder).
    gaea.imports = [
      inputs.microvm.nixosModules.host
      {
        microvm.vms.builder.extraModules = [ inputs.hercules-ci-agent.nixosModules.multi-agent-service ];
      }
    ];

    # From the inventory, so the checks follow machine and control-plane changes.
    pik8s3.uptime =
      let
        inherit (inputs.nixpkgs) lib;
        rosequartz = import ./clan/rosequartz-cluster.nix;
        ipOf = name: rosequartz.machines.${name}.ip;
        etcdMembers = lib.attrNames (lib.filterAttrs (_: m: m.role == "control-plane") rosequartz.machines);
      in
      {
        hosts = builtins.mapAttrs (_: host: host.ip) (builtins.removeAttrs managed [ "pik8s3" ]);
        inherit (rosequartz) vip;
        apiservers = lib.genAttrs rosequartz.services.apiserver.machines ipOf;
        etcd = lib.genAttrs etcdMembers ipOf;
        # status.php answers without a login and reports maintenance mode and pending
        # upgrades.
        services.nextcloud = {
          url = "https://cloud.thecluster.io/status.php";
          conditions = [
            "[STATUS] == 200"
            "[BODY].installed == true"
            "[BODY].maintenance == false"
            "[BODY].needsDbUpgrade == false"
          ];
        };
        services.attic = {
          url = "http://${managed.gaea.ip}:8080/thecluster/nix-cache-info";
          conditions = [ "[STATUS] == 200" ];
          page = true;
        };
        # A 401 tells the API apart from a Cloudflare error page.
        services.hercules-ci = {
          url = "https://hercules-ci.com/api/v1/accounts/me";
          conditions = [ "[STATUS] == 401" ];
          page = true;
        };
        pushes = {
          # Workstations suspend, so only a low-disk push from one pages.
          disk = builtins.mapAttrs (
            _: host: lib.optionalAttrs (builtins.elem "workstation" host.tags) { heartbeat = null; }
          ) managed;
          builder = {
            disk = { };
            agents = { };
            # builder-gc's timer is 1h.
            gc.heartbeat = "2h";
          };
          attic.disk = { };
        };
      };
  };
}
