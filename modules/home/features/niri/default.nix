{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeFeatures.niri;

  niriConfig = pkgs.runCommand "niri-noctalia-config.kdl" { } ''
    cp ${lib.getOutput "doc" pkgs.niri}/share/doc/niri/default-config.kdl "$out"

    substituteInPlace "$out" \
      --replace-fail 'spawn-at-startup "waybar"' 'spawn-at-startup "noctalia"' \
      --replace-fail 'Mod+D hotkey-overlay-title="Run an Application: fuzzel" { spawn "fuzzel"; }' 'Mod+Space hotkey-overlay-title="Open the Noctalia launcher" { spawn "noctalia" "msg" "panel-toggle" "launcher"; }' \
      --replace-fail 'Super+Alt+L hotkey-overlay-title="Lock the Screen: swaylock" { spawn "swaylock"; }' 'Super+Alt+L hotkey-overlay-title="Lock the Screen: Noctalia" { spawn "noctalia" "msg" "session" "lock"; }'

    cat >> "$out" <<'KDL'

    // Noctalia integration managed by Home Manager.
    window-rule {
        geometry-corner-radius 20
        clip-to-geometry true
    }

    window-rule {
        match app-id="dev.noctalia.Noctalia"
        open-floating true
        default-column-width { fixed 1080; }
        default-window-height { fixed 920; }
    }

    debug {
        honor-xdg-activation-with-invalid-serial
    }
    KDL

    ${pkgs.niri}/bin/niri validate --config "$out"
  '';
in
{
  options.homeFeatures.niri.enable = lib.mkEnableOption "Niri Wayland compositor with Noctalia integration";

  config = lib.mkIf cfg.enable {
    assertions = [
      {
        assertion = config.homeFeatures.noctalia.enable;
        message = "homeFeatures.niri requires homeFeatures.noctalia";
      }
    ];

    home.packages = with pkgs; [
      alacritty
      brightnessctl
      niri
      playerctl
      wireplumber
    ];

    home.sessionVariables.NIXOS_OZONE_WL = "1";

    xdg.configFile."niri/config.kdl".source = niriConfig;
  };
}
