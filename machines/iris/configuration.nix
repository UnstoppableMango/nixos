{ pkgs, ... }:
{
  imports = [
    ../../modules/ceph
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Dell R410. Firmware mode unverified, so take castor's dual-mode grub: BIOS
  # grub on the disk plus an EFI removable-path loader on the ESP.
  boot.loader.grub = {
    enable = true;
    efiSupport = true;
    efiInstallAsRemovable = true;
  };

  # https://nixos.wiki/wiki/Power_Management#systemd_sleep
  systemd.sleep.settings.Sleep = {
    AllowSuspend = "no";
    AllowHibernation = "no";
    AllowHybridSleep = "no";
    AllowSuspendThenHibernate = "no";
  };

  networking = {
    hostName = "iris";
    useDHCP = false;
  };

  hardware.facter.detected.dhcp.enable = false;

  # TODO: match by MAC, as apollo does, once the facter report is in. eno1 and
  # eno2 are the names the R410's two onboard ports are expected to take.
  systemd.network.networks."10-lan" = {
    matchConfig.Name = "eno1";
    address = [ "10.0.69.15/24" ];
    gateway = [ "10.0.69.1" ];
  };

  # A DHCP lease on the second port would add a second default route, which
  # the strict reverse-path filter then trips over.
  systemd.network.networks."10-unused" = {
    matchConfig.Name = "eno2";
    linkConfig.ActivationPolicy = "down";
  };

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    kubernetes-helm
    ldns
  ];
}
