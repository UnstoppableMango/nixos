{ lib, pkgs, config, ... }:
{
  options.hardware.raspberry-pi."4".usbBoot.enable =
    lib.mkEnableOption "USB-first boot order via EEPROM (BOOT_ORDER=0xf14)";

  config = lib.mkIf config.hardware.raspberry-pi."4".usbBoot.enable {
    # Idempotent — only updates EEPROM if BOOT_ORDER differs.
    # A reboot is required after the first update for the change to take effect.
    systemd.services.rpi-eeprom-usb-boot = {
      description = "Configure RPi4 EEPROM for USB-first boot order";
      wantedBy = [ "multi-user.target" ];
      after = [ "local-fs.target" ];
      serviceConfig = {
        Type = "oneshot";
        RemainAfterExit = true;
      };
      script = ''
        current=$(${pkgs.raspberrypi-eeprom}/bin/rpi-eeprom-config)
        current_order=$(echo "$current" | grep '^BOOT_ORDER=' | cut -d= -f2)
        if [ "$current_order" != "0xf14" ]; then
          echo "$current" \
            | sed 's/^BOOT_ORDER=.*/BOOT_ORDER=0xf14/' \
            | ${pkgs.raspberrypi-eeprom}/bin/rpi-eeprom-config --apply -
          echo "EEPROM updated: BOOT_ORDER=0xf14 (USB-first). Reboot required."
        else
          echo "EEPROM already configured for USB-first boot."
        fi
      '';
    };
  };
}
