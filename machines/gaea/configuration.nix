{ pkgs, ... }:
{
  imports = [
    ../../modules/arc-runner-store
    ../../modules/attic
    ../../modules/ceph
    ../../modules/ceph-cluster-network
    ../../modules/ci-limits
    ../../modules/dns
    ../../modules/nix
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  arcRunnerStore.enable = true;

  # Lets the agents here take derivations that need AVX2, which zeus lacks (#416).
  nix.settings.extra-system-features = [ "gccarch-x86-64-v3" ];

  ciLimits = {
    memoryMax = 128;
    agentMemoryMax = 16;
    maxJobs = 16;
    cores = 8;
    reservedCpu = 16;
  };

  boot.loader = {
    efi.canTouchEfiVariables = true;
    systemd-boot = {
      enable = true;
      configurationLimit = 25;
    };
  };

  # https://nixos.wiki/wiki/Power_Management#systemd_sleep
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  # ixgbe refuses the aggregator's non-Intel SFP+ modules otherwise.
  boot.extraModprobeConfig = "options ixgbe allow_unsupported_sfp=1";

  cephClusterNetwork = {
    enable = true;
    interface = "enp99s0f1";
    address = "10.0.70.11";
    rangeStart = "10.0.70.96";
    rangeEnd = "10.0.70.127";
  };

  # eno1 is cabled to GS724Tv4 `g1`.
  networking = {
    hostName = "gaea";
    useDHCP = false;

    defaultGateway = {
      address = "10.0.69.1";
      interface = "eno1";
    };

    interfaces.eno1 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.11";
          prefixLength = 24;
        }
      ];
    };
  };

  atticVm.interface = "eno1";

  hardware.facter.detected.dhcp.enable = false;

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    kubernetes-helm
    ldns
  ];

}
