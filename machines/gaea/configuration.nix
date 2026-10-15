{ pkgs, ... }:
{
  imports = [
    ../../modules/arc-runner-store
    ../../modules/ceph
    ../../modules/ceph-cluster-network
    ../../modules/ci-limits
    ../../modules/dns
    ../../modules/nix
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  arcRunnerStore.enable = true;

  # EPYC (Zen 2) has AVX2. Advertised so the Hercules agents here take the
  # derivations that require it (nixpkgs' bun), which zeus cannot run (#416).
  nix.settings.extra-system-features = [ "gccarch-x86-64-v3" ];

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

  # enp99s0f1 is the X520-2 port cabled to the aggregator. ixgbe refuses SFP+
  # modules and DACs that are not Intel-coded, and the aggregator's are not.
  boot.extraModprobeConfig = "options ixgbe allow_unsupported_sfp=1";

  cephClusterNetwork = {
    enable = true;
    interface = "enp99s0f1";
    address = "10.0.70.11";
    rangeStart = "10.0.70.96";
    rangeEnd = "10.0.70.127";
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
