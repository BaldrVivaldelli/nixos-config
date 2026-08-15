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
      python3Packages.detect-secrets
      gh
      glab

      # Lenguajes y toolchains.
      python3
      uv
      nodejs
      go
      rustc
      cargo
      elan

      # Aplicaciones gráficas instalables en el perfil del usuario.
      chromium
      kiro

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

    home.activation.holodeckSecretScannerHook = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
      repo_path=${lib.escapeShellArg config.homeFeatures.shell.repoPath}
      if [ -d "$repo_path/.git" ] && [ -x "$repo_path/.githooks/pre-commit" ]; then
        $DRY_RUN_CMD ${pkgs.git}/bin/git -C "$repo_path" config --local core.hooksPath .githooks
      fi
    '';

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
