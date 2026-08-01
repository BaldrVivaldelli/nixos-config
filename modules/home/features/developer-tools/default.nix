{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeFeatures.developerTools;

  vscodiumExtensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace (
    builtins.fromJSON (builtins.readFile ../../../nixos/features/vscodium/extensions.json)
  );

  holodeck = pkgs.callPackage ../../../../packages/holodeck {
    coreSource = ../../../../holodeck/core;
  };
in
{
  options.homeFeatures.developerTools.enable = lib.mkEnableOption "herramientas y aplicaciones personales de desarrollo";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      # Utilidades generales que antes estaban en environment.systemPackages.
      wget
      curl

      # Git y plataformas de repositorios.
      git
      git-lfs
      delta
      lazygit
      gh
      glab

      # Lenguajes y toolchains.
      python3
      uv
      nodejs
      elan

      # Aplicaciones gráficas instalables en el perfil del usuario.
      chromium

      # Identidad, SSH y utilidades de escritorio.
      gnupg
      openssh
      freerdp
      xdg-utils

      # Herramienta propia del repositorio.
      holodeck
    ];

    home.sessionVariables = {
      BROWSER = "chromium";
      EDITOR = "codium";
      VISUAL = "codium";
    };

    xdg.mimeApps = {
      enable = true;
      defaultApplications = {
        "text/html" = "chromium-browser.desktop";
        "text/xml" = "chromium-browser.desktop";
        "application/xhtml+xml" = "chromium-browser.desktop";
        "application/xml" = "chromium-browser.desktop";
        "application/pdf" = "chromium-browser.desktop";
        "x-scheme-handler/http" = "chromium-browser.desktop";
        "x-scheme-handler/https" = "chromium-browser.desktop";
        "x-scheme-handler/about" = "chromium-browser.desktop";
        "x-scheme-handler/unknown" = "chromium-browser.desktop";
      };
    };

    programs.vscodium = {
      enable = true;
      package = pkgs.vscodium;

      profiles.default = {
        extensions = vscodiumExtensions;
        userSettings = {
          "git.autofetch" = true;
          "workbench.colorTheme" = "Catppuccin Frappé";
          "workbench.iconTheme" = "catppuccin-mocha";
        };
      };
    };
  };
}
