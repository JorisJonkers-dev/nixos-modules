{
  config,
  lib,
  ...
}: let
  cfg = config.platformBlueprints.hardware.laptop;
in {
  options.platformBlueprints.hardware.laptop = {
    enable = lib.mkEnableOption "laptop support: power profiles, firmware updates, touchpad, lid and suspend";

    convertible.enable = lib.mkEnableOption "2-in-1 convertible support: auto-rotate, on-screen keyboard and tablet mode";

    batteryChargeThreshold = lib.mkOption {
      type = lib.types.nullOr (lib.types.ints.between 50 100);
      default = null;
      description = "Stop charging at this percentage, on firmware that supports it; null leaves the firmware default";
    };
  };

  config = lib.mkIf cfg.enable (lib.mkMerge [
    {
      services.power-profiles-daemon.enable = lib.mkDefault true;
      services.fwupd.enable = lib.mkDefault true;
      services.libinput.enable = lib.mkDefault true;
      services.upower.enable = lib.mkDefault true;

      # A docked lid usually means an external keyboard and screen are in use,
      # so suspending there would kill work the user is still doing.
      services.logind.settings.Login = {
        HandleLidSwitch = lib.mkDefault "suspend";
        HandleLidSwitchExternalPower = lib.mkDefault "suspend";
        HandleLidSwitchDocked = lib.mkDefault "ignore";
      };
    }

    (lib.mkIf cfg.convertible.enable {
      # GNOME reads the accelerometer through iio-sensor-proxy for auto-rotate
      # and shows its on-screen keyboard in tablet mode by itself.
      hardware.sensor.iio.enable = true;
    })

    (lib.mkIf (cfg.batteryChargeThreshold != null) {
      # The limit lives per battery and only on firmware that implements it, so
      # the unit writes to whatever exists and leaves the rest alone.
      systemd.services.laptop-charge-threshold = {
        description = "Cap battery charging at ${toString cfg.batteryChargeThreshold}%";
        wantedBy = ["multi-user.target"];
        after = ["systemd-udev-settle.service"];
        serviceConfig = {
          Type = "oneshot";
          RemainAfterExit = true;
        };
        script = ''
          for threshold in /sys/class/power_supply/BAT*/charge_control_end_threshold; do
            [ -e "$threshold" ] || continue
            echo ${toString cfg.batteryChargeThreshold} > "$threshold"
          done
        '';
      };
    })
  ]);
}
