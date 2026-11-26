{
  config,
  lib,
  pkgs,
  ...
}:
let
  vmMemory = lib.foldl' (sum: vm: sum + vm.config.config.microvm.mem / 1024) 0 (
    lib.attrValues config.microvm.vms
  );
  nixDaemonMemory = 16;
  harmoniaMemory = 2;
in
{
  imports = [
    ../../modules/arc-runner-store
    ../../modules/attic
    ../../modules/builder
    ../../modules/ceph
    ../../modules/ceph-cluster-network
    ../../modules/dns
    ../../modules/nix
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  arcRunnerStore.enable = true;

  # No swap, so capping the host's builds keeps the OOM killer off the OSDs.
  # Half the default weights, so kubelet and the OSDs win contention.
  systemd.services.nix-daemon.serviceConfig = {
    MemoryMax = "${toString nixDaemonMemory}G";
    CPUWeight = 50;
    IOWeight = 50;
  };
  nix.settings = {
    max-jobs = 4;
    cores = 8;
  };
  systemd.services.harmonia.serviceConfig.MemoryMax = "${toString harmoniaMemory}G";

  services.kubernetes.kubelet.extraConfig = {
    # About 4 GiB for the rest of the host.
    systemReserved = {
      cpu = "16";
      memory = "${toString (vmMemory + nixDaemonMemory + harmoniaMemory + 4)}Gi";
    };
    kubeReserved = {
      cpu = "1";
      memory = "2Gi";
    };
    evictionHard."memory.available" = "2Gi";
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

  # sg_ses needs /dev/sg* to blink the expander's bay LEDs.
  boot.kernelModules = [ "sg" ];

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

  vmHost.interface = "eno1";

  hardware.facter.detected.dhcp.enable = false;

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    kubernetes-helm
    ldns
  ];

}
