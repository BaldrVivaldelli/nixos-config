{
  config,
  lib,
  ...
}:

let
  cfg = config.homeFeatures.noctalia;
in
{
  options.homeFeatures.noctalia.enable = lib.mkEnableOption "Noctalia v5 Wayland desktop shell";

  config = lib.mkIf cfg.enable {
    programs.noctalia = {
      enable = true;

      # Noctalia recommends compositor startup. This stays disabled until the
      # repository declares either Hyprland or Niri and its startup command.
      systemd.enable = false;

      settings.theme = {
        mode = "dark";
        source = "builtin";
        builtin = "Catppuccin";
      };
    };
  };
}
