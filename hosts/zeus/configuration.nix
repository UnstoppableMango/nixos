{ pkgs, ... }:
{
  nix.settings = {
    extra-substituters = [
      "https://ncps.thecluster.lan"
      "https://nix-community.cachix.org"
      "https://unstoppablemango.cachix.org"
    ];
    extra-trusted-public-keys = [
      "ncps.thecluster.lan:D8fcKW2/D+zjKOABa3bDjEe8x+EPZpXnBDm+XwtNrhI="
      "nix-community.cachix.org-1:mB9FSh9qf2dCimDSUo8Zy7bkq5CX+/rkCWyvRCYg3Fs="
      "unstoppablemango.cachix.org-1:m7uEI6X1Ov8DyFWJQX4WsRFRWFuzRW5c/Xms8ZaP74U="
    ];
    experimental-features = [
      "nix-command"
      "flakes"
    ];
  };

  imports = [
    ./disk-config.nix
  ];

  boot.loader = {
    # grub = {
    #   devices = [ "/dev/nvme0n1" ];
    #   efiSupport = true;
    #   efiInstallAsRemovable = true;
    # };

    efi.canTouchEfiVariables = true;
    systemd-boot = {
      enable = true;
      configurationLimit = 25;
    };
  };

  # https://nixos.wiki/wiki/Power_Management#systemd_sleep
  systemd.sleep.extraConfig = ''
    AllowSuspend=no
    AllowHibernation=no
    AllowHybridSleep=no
    AllowSuspendThenHibernate=no
  '';

  networking = {
    hostName = "agreus";
    useDHCP = false;

    networkmanager = {
      enable = true;

      # https://wiki.nixos.org/wiki/NetworkManager#DNS_Management
      insertNameservers = [
        "192.168.1.44"
        "192.168.1.45"
        "1.1.1.1"
        "1.0.0.1"
      ];
    };
  };

  services.openssh.enable = true;

  environment.systemPackages = with pkgs; [
    curl
    gitMinimal
  ];

  # https://mynixos.com/nixpkgs/option/users.mutableUsers
  users.mutableUsers = true;
  users.users =
    let
      hadesKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEwW6dUPKvKXXzj+gKJS7EXh6UzyLjzatrcPXa0Y2qvz erik@hades";
      darterKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDB02UwohkEJGpb8Uud4bNQa73X9WvwQcbsRr1M8c7nztbnUCCeLBTyCtRTMnR6dmoQ3xfGLbv55nlTFT/s6ZZKWEAql/gPJoBF9nEr0622IJQ6VPIpgcI8eA2YDwYA0l19Bji4u3VbTMB+M3Tz7JRmKqHo5bUvnZWi2cp+G5Hh2f2k0lQOa9ttjvVlLBQLCJV8NmCxikJS0ZuH2+KJPT2DVsY8dMZ2fQHh1/DI+ZAo6V1qjEU4SQKjpdIrUsPt9Ah1CBU7W3tG57+aYCoaay/BuUY4zlewxGdn3MAv/mjyqF6WgkzCilr7VBnO8CUgzLGu6F+8ljEJVZ5zqyTGfuni/069qMROEp6abhQe7MGToqFgsDkIJhSihomUNylM2piVFobZTeqGBXqh8h3W1fkQHsfMjYbkYP6kHx7yZ03Xw7X+4ZfySZ4s1PqvJE1ZALHdpzYSDK06+iqbJ3ZA/lpipg+Mzx7iRrD3CsPjzgi1iE6w5DVu5xAMIZIRFetTIAs= erik@darter";
    in
    {
      erik = {
        isNormalUser = true;
        home = "/home/erik";
        initialPassword = "Password123!";
        extraGroups = [ "wheel" ];
        openssh.authorizedKeys.keys = [
          hadesKey
          darterKey
        ];
      };

      root = {
        openssh.authorizedKeys.keys = [
          hadesKey
        ];
      };
    };

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

  # This value determines the NixOS release from which the default
  # settings for stateful data, like file locations and database versions
  # on your system were taken. It‘s perfectly fine and recommended to leave
  # this value at the release version of the first install of this system.
  # Before changing this value read the documentation for this option
  # (e.g. man configuration.nix or on https://nixos.org/nixos/options.html).
  system.stateVersion = "25.05"; # Did you read the comment?
}
