{ pkgs, ... }:
{
  imports = [
    ../../modules/arc-runner-store
    ../../modules/ceph
    ../../modules/ci-limits
    ../../modules/dns
    ../../modules/nix
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  arcRunnerStore.enable = true;

  # 128 threads, 503 GB, shared with OSDs and the Actions runner pods.
  ciLimits = {
    memoryMax = 128;
    agentMemoryMax = 16;
    maxJobs = 16;
    cores = 8;
    reservedCpu = 16;
  };

  # EPYC 7502 rack box whose firmware is in UEFI mode, so it takes
  # systemd-boot rather than zeus's legacy-BIOS grub.
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

  # eno1 is the port cabled to GS724Tv4 `g1`. eno2 stays unconfigured; it
  # carried the previous cluster's 10.69.0.0/16 network on a VLAN 69 subinterface.
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

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    kubernetes-helm
    ldns
  ];

}
