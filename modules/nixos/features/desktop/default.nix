{ lib, ... }:

{
  imports = [
    ./gnome.nix
  ];

  options.features.desktop = {
    enable = lib.mkEnableOption "desktop environment";

    environment = lib.mkOption {
      type = lib.types.enum [ "gnome" ];
      default = "gnome";
      description = "Desktop environment to enable.";
    };

    keyboard = {
      layout = lib.mkOption {
        type = lib.types.str;
        default = "us";
        description = "XKB keyboard layout.";
      };

      variant = lib.mkOption {
        type = lib.types.str;
        default = "";
        description = "XKB keyboard variant.";
      };
    };
  };
}
