{
  config,
  lib,
  pkgs,
  user,
  holodeckIr,
  ...
}:

let
  cfg = config.homeFeatures.noctalia;
  holodeck = pkgs.callPackage ../../../../packages/holodeck {
    coreSource = ../../../../holodeck/core;
  };
  holodeckctl = pkgs.callPackage ../../../../packages/holodeckctl {
    inherit holodeck;
    defaultRepoPath = user.repoPath;
  };
  plugin = pkgs.callPackage ../../../../packages/holodeck-noctalia-plugin {
    noctalia = config.programs.noctalia.package;
    inherit holodeckctl;
  };
in
{
  options.homeFeatures.noctalia.enable = lib.mkEnableOption "Noctalia v5 Wayland desktop shell";

  config = lib.mkIf cfg.enable {
    programs.noctalia = {
      enable = true;

      # Noctalia recommends compositor startup. This stays disabled until the
      # repository declares either Hyprland or Niri and its startup command.
      systemd.enable = false;

      settings = {
        theme = {
          inherit (holodeckIr.appearance.theme) mode builtin;
          source = "builtin";
        };

        plugins.enabled = [ "holodeck/control" ];

        # Keep Noctalia's default end lane and add Holodeck beside the native
        # Control Center and session actions. The compact asset is designed for
        # this 16–24 px context and opens the same plugin panel as the launcher.
        bar.main.end = [
          "media"
          "tray"
          "notifications"
          "clipboard"
          "network"
          "bluetooth"
          "volume"
          "brightness"
          "battery"
          "holodeck/control:config"
          "control-center"
          "session"
        ];
      };
    };

    home.packages = [ holodeckctl ];

    # Noctalia always discovers this local XDG data source after its official
    # and community sources. The Nix-store symlink keeps the plugin immutable
    # without replacing those upstream catalogs.
    xdg.dataFile."noctalia/plugins/holodeck-control".source = plugin;

    xdg.desktopEntries.holodeck-control = {
      name = "Holodeck Control";
      genericName = "Holodeck desktop configuration";
      comment = "Configure and apply the declarative desktop profile";
      exec = "${lib.getExe config.programs.noctalia.package} msg panel-toggle holodeck/control:control";
      icon = "${plugin}/assets/holodeck-control.png";
      terminal = false;
      categories = [
        "Settings"
        "System"
      ];
    };
  };
}
