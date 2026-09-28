{ pkgs, ... }:
{
  imports = [
    ../../modules/ceph
    ./disk-config.nix
  ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Dell R410 with its firmware in UEFI mode, so it takes gaea's systemd-boot.
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

    # Pod traffic for VLAN 1 goes through pfSense like it does from every other
    # node, rather than out eno2's connected route. 10.1.0.0/16 is the
    # rosequartz pod CIDR.
    routes = [
      {
        Destination = "192.168.1.0/24";
        Gateway = "10.0.69.1";
        Table = 200;
      }
    ];
    routingPolicyRules = [
      {
        From = "10.1.0.0/16";
        To = "192.168.1.0/24";
        Table = 200;
        Priority = 100;
      }
    ];
  };

  # VLAN 1 leg, on-link only. No gateway, so the default route stays on eno1.
  # VLAN 1 clients reach iris here; a VLAN 1 client using 10.0.69.15 gets
  # replies out this port instead of back through pfSense.
  systemd.network.networks."10-vlan1" = {
    matchConfig.Name = "eno2";
    address = [ "192.168.1.15/24" ];
  };

  # eno2 carries only iris's own traffic, so iris never forwards between the
  # VLANs around pfSense. mangle runs ahead of kube-proxy's nat and filter
  # rules, which would otherwise accept NodePort traffic arriving here.
  networking.firewall = {
    extraCommands = ''
      iptables -t mangle -D PREROUTING -i eno2 ! -d 192.168.1.15 -j DROP 2>/dev/null || true
      iptables -t mangle -D POSTROUTING -o eno2 ! -s 192.168.1.15 -j DROP 2>/dev/null || true
      iptables -t mangle -A PREROUTING -i eno2 ! -d 192.168.1.15 -j DROP
      iptables -t mangle -A POSTROUTING -o eno2 ! -s 192.168.1.15 -j DROP
    '';
    extraStopCommands = ''
      iptables -t mangle -D PREROUTING -i eno2 ! -d 192.168.1.15 -j DROP 2>/dev/null || true
      iptables -t mangle -D POSTROUTING -o eno2 ! -s 192.168.1.15 -j DROP 2>/dev/null || true
    '';
  };

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
    kubectl
    kubernetes-helm
    ldns
  ];
}
