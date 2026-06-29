{ lib, config, ... }:
{
  options.dotfiles.unifi.enable = lib.mkEnableOption "unifi controller";

  config = lib.mkIf config.dotfiles.unifi.enable {
    services.unifi = {
      enable = true;
      openFirewall = true;
    };

    # Prevent autostart at boot; manage manually with systemctl start/stop unifi
    systemd.services.unifi.wantedBy = lib.mkForce [ ];
  };
}
