{ inputs, config, ... }:
{
  flake.homeModules.erik = config.modules.homeManager.erik;
  flake.modules.homeManager.erik =
    { pkgs, ... }:
    {
      imports = with inputs.dotfiles.modules.homeManager; [
        brave
        emacs
        erik
        ghostty
        gnome
        kitty
        vscode
        zed
      ];

      home.packages = with pkgs; [
        github-desktop
        seabird
        webex
      ];

      programs.lutris.enable = true;

      programs.git.signing = {
        format = "openpgp";
        key = "264283BBFDC491BC";
        signByDefault = true;
      };
    };

  flake.nixosModules.erik = config.modules.nixos.erik;
  flake.modules.nixos.erik =
  let
    hadesKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIEwW6dUPKvKXXzj+gKJS7EXh6UzyLjzatrcPXa0Y2qvz erik@hades";
    darterKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAABgQDB02UwohkEJGpb8Uud4bNQa73X9WvwQcbsRr1M8c7nztbnUCCeLBTyCtRTMnR6dmoQ3xfGLbv55nlTFT/s6ZZKWEAql/gPJoBF9nEr0622IJQ6VPIpgcI8eA2YDwYA0l19Bji4u3VbTMB+M3Tz7JRmKqHo5bUvnZWi2cp+G5Hh2f2k0lQOa9ttjvVlLBQLCJV8NmCxikJS0ZuH2+KJPT2DVsY8dMZ2fQHh1/DI+ZAo6V1qjEU4SQKjpdIrUsPt9Ah1CBU7W3tG57+aYCoaay/BuUY4zlewxGdn3MAv/mjyqF6WgkzCilr7VBnO8CUgzLGu6F+8ljEJVZ5zqyTGfuni/069qMROEp6abhQe7MGToqFgsDkIJhSihomUNylM2piVFobZTeqGBXqh8h3W1fkQHsfMjYbkYP6kHx7yZ03Xw7X+4ZfySZ4s1PqvJE1ZALHdpzYSDK06+iqbJ3ZA/lpipg+Mzx7iRrD3CsPjzgi1iE6w5DVu5xAMIZIRFetTIAs= erik@darter";
  in
  {
    nixpkgs.overlays = [ inputs.dotfiles.overlays.default ];

    users.users.erik.openssh.authorizedKeys.keys = [
      hadesKey
      darterKey
    ];

    home-manager = {
      useGlobalPkgs = true;
      useUserPackages = true;
      backupFileExtension = "bak";

      users.erik = {
        imports = [
          inputs.nixvim.homeModules.nixvim
          config.modules.homeManager.erik
        ];
      };
    };
  };
}
