{ config, lib, ... }:

let
  cfg = config.features.desktop;
in
{
  config = lib.mkIf (cfg.enable && cfg.environment == "niri") {
    programs.niri.enable = true;

    services = {
      displayManager = {
        sddm.enable = true;
        defaultSession = "niri";
      };

      power-profiles-daemon.enable = true;
      upower.enable = true;

      xserver = {
        enable = true;
        xkb = {
          layout = cfg.keyboard.layout;
          variant = cfg.keyboard.variant;
        };
      };
    };

    hardware.bluetooth.enable = true;
    networking.networkmanager.enable = true;

    # Electron applications use their native Wayland backend in the Niri session.
    environment.sessionVariables.NIXOS_OZONE_WL = "1";
  };
}
