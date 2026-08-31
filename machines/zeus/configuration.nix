{ pkgs, ... }:
{
  nix.settings = {
    extra-substituters = [
      "https://nix-community.cachix.org"
      "https://unstoppablemango.cachix.org"
    ];
    extra-trusted-public-keys = [
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "unstoppablemango.cachix.org-1:m7uEI6X1Ov8DyFWJQX4WsRFRWFuzRW5c/Xms8ZaP74U="
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  imports = [ ./disk-config.nix ];

  nixpkgs.hostPlatform = "x86_64-linux";

  # Dual Xeon E5-2670 tower whose firmware is in legacy BIOS mode, so it takes
  # grub rather than gaea's systemd-boot. efiSupport keeps the hybrid layout
  # bootable if the firmware ever switches to UEFI.
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

  # enp6s0 is the port cabled to GS724Tv4 `g18`. The board's other five NICs
  # stay unconfigured; two of them carried the previous cluster's 10.69.0.0/16
  # network.
  networking = {
    hostName = "zeus";
    useDHCP = false;

    defaultGateway = {
      address = "10.0.69.1";
      interface = "enp6s0";
    };

    nameservers = [ "10.0.69.1" ];

    interfaces.enp6s0 = {
      useDHCP = false;
      ipv4.addresses = [
        {
          address = "10.0.69.10";
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

  # TODO: Move to cert service
  security.pki.certificates = [
    # thecluster.lan Nginx CA
    ''
      -----BEGIN CERTIFICATE-----
      MIIDqTCCA1ugAwIBAgIRAP3DFbRphLU1I5G7SgUWB8cwBQYDK2VwMDsxCzAJBgNV
      BAYTAlVTMRAwDgYDVQQKEwdVbk1hbmdvMRowGAYDVQQDExFVbk1hbmdvIEF1dGhv
      cml0eTAeFw0yNDA3MjIwNTI1NTdaFw00OTA3MTYwNTI1NTdaMFIxCzAJBgNVBAYT
      AlVTMRAwDgYDVQQKEwdVbk1hbmdvMRkwFwYDVQQLExBVbnN0b3BwYWJsZU1hbmdv
      MRYwFAYDVQQDEw10aGVjbHVzdGVyLmlvMIICIjANBgkqhkiG9w0BAQEFAAOCAg8A
      MIICCgKCAgEAxdhA+xxuQYucY2eDgHg5paLEOT6dHGTlULhu5n3HwmGy8PDUSFPR
      hMUwWgurKEZlNdA77I2DP2pBfyT3FqGosbWtke2HFq3zOaap1UCHkd6NuYb7rEwI
      Nlcd3cTw+/U8yUGJsjkaS2VBbbTyuWAcGvguQmpf/r5Su8ilDN/4MFMan6qRCGoB
      yTPB8DfBsqcGUgu94mNaE1onnAisMYERWeED1lnlZKuo+Ff8dp9uS+xM/zFTRtSs
      BYtF/RALUrH964UiXW3vLA0kzfXDc3b6RKTGT0jl5/oLHHSi38sRLdXxogVdZLFm
      XLYm4fuHJRCMHm0/ejM2KvIK9DT05QsqQCw1IMtbZxsLGG7PgoheaDIiXavx0A/c
      yCwG+8WrRJearruHb1JDVAVMufFcHQX+UlUvIXQrjeVSfsPLiVbYLSg/VLjwLPgP
      /EkF14lxLxObkKLOmLbyOHP6KybdATgHJeZVK9BA6awmlQASSKwvrmwkdze7ESkG
      JTh495w3N3qcQ2DidQ2pn59moN43nGTU6cvPgqDR2UZzxUvh10fk45Ayj4LVXdsp
      APKOW1dHkk55VYEI9+MMzjlV+qPlH4Am2R40o/B+KQh1HkpUXz7lsFpkjEraBBia
      qMdDxT2qdbR9nyBR01lcXujcGa/pXqNNV93fVrrPT9VakcngFiqQ1i0CAwEAAaNj
      MGEwDgYDVR0PAQH/BAQDAgGGMA8GA1UdEwEB/wQFMAMBAf8wHQYDVR0OBBYEFJdi
      KvNTkRcWLmJ8vcD2/AmuCOKiMB8GA1UdIwQYMBaAFOYurdBkToYbj1m0tvjcDvQY
      j7dUMAUGAytlcANBALA6/GiSW3js9iarFiqloS+jI9kfqHABufe4XDuiZXL6sB9K
      1bJtYQRzzKLOfQ5/GPf44JIhJPR5k2h4nkZ17gE=
      -----END CERTIFICATE-----
    ''
  ];
}
