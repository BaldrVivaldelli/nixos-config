{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeFeatures.developerTools;

  holodeck = pkgs.callPackage ../../../../packages/holodeck {
    coreSource = ../../../../holodeck/core;
  };
in
{
  options.homeFeatures.developerTools.enable =
    lib.mkEnableOption "herramientas y aplicaciones personales de desarrollo";

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
      vscodium

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
  };
}
