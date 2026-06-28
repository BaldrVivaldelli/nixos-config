{ config, lib, ... }:

let
  cfg = config.features.desktop;
in
{
  config = lib.mkIf (cfg.enable && cfg.environment == "gnome") {
    services.xserver = {
      enable = true;
      xkb = {
        layout = cfg.keyboard.layout;
        variant = cfg.keyboard.variant;
      };
    };

    services.displayManager.gdm.enable = true;
    services.desktopManager.gnome.enable = true;
  };
}
