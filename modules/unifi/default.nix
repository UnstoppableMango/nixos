{
  pkgs,
  lib,
  config,
  ...
}:
{
  options.dotfiles.unifi.enable = lib.mkEnableOption "unifi controller";

  config = lib.mkIf config.dotfiles.unifi.enable {
    services.unifi = {
      enable = true;
      openFirewall = true;
      # TEMP: bridge mongo 7.0 -> 8.2 FCV upgrade. Data dir FCV is still "7.0";
      # mongod 8.2 refuses to start against it. Boot once on 8.0.x, run
      # `db.adminCommand({setFeatureCompatibilityVersion: "8.0", confirm: true})`,
      # then revert this override back to `pkgs.mongodb-ce`.
      mongodbPackage = pkgs.mongodb-ce.overrideAttrs (old: rec {
        version = "8.0.15";
        src = pkgs.fetchurl {
          url = "https://fastdl.mongodb.org/linux/mongodb-linux-x86_64-ubuntu2404-${version}.tgz";
          hash = "sha256-hHlTsXbzDBhesK6hrGV27zXBBd7uEFlt/5QDJFn5aFA=";
        };
      });
    };

    # Prevent autostart at boot; manage manually with systemctl start/stop unifi
    systemd.services.unifi.wantedBy = lib.mkForce [ ];
  };
}
