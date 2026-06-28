{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.browser;

  chromiumCommand = pkgs.writeShellApplication {
    name = "chromium";
    runtimeInputs = [ cfg.package ];
    text = ''
      exec ${lib.escapeShellArg cfg.command} "$@"
    '';
  };
in
{
  options.features.browser = {
    enable = lib.mkEnableOption "desktop browser";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.chromium;
      defaultText = lib.literalExpression "pkgs.chromium";
      description = "Browser package to install and configure through Chromium policies.";
    };

    command = lib.mkOption {
      type = lib.types.str;
      default = "chromium-browser";
      description = "Executable provided by the browser package.";
    };

    desktopFile = lib.mkOption {
      type = lib.types.str;
      default = "chromium-browser.desktop";
      description = "Desktop file used for xdg default browser associations.";
    };

    homepage = lib.mkOption {
      type = lib.types.nullOr lib.types.str;
      default = null;
      description = "Optional Chromium homepage URL.";
    };

    extensions = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Chromium extension IDs to install.";
    };

    extraOpts = lib.mkOption {
      type = lib.types.attrs;
      default = { };
      description = "Extra Chromium enterprise policy options.";
    };

    search = {
      enable = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = "Whether to configure a default search provider.";
      };

      url = lib.mkOption {
        type = lib.types.str;
        default = "https://www.google.com/search?q={searchTerms}";
        description = "Search URL for Chromium's default search provider.";
      };

      suggestUrl = lib.mkOption {
        type = lib.types.str;
        default = "https://www.google.com/complete/search?client=chrome&q={searchTerms}";
        description = "Suggest URL for Chromium's default search provider.";
      };
    };

    defaultBrowser.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to make Chromium the default browser for web links.";
    };
  };

  config = lib.mkIf cfg.enable {
    programs.chromium = {
      enable = true;
      extensions = cfg.extensions;
      extraOpts = cfg.extraOpts;
      homepageLocation = lib.mkIf (cfg.homepage != null) cfg.homepage;
      defaultSearchProviderEnabled = cfg.search.enable;
      defaultSearchProviderSearchURL = lib.mkIf cfg.search.enable cfg.search.url;
      defaultSearchProviderSuggestURL = lib.mkIf cfg.search.enable cfg.search.suggestUrl;
    };

    environment = {
      sessionVariables.BROWSER = cfg.command;
      systemPackages = [
        cfg.package
        chromiumCommand
      ];
    };

    xdg.mime = lib.mkIf cfg.defaultBrowser.enable {
      enable = true;
      defaultApplications = {
        "text/html" = cfg.desktopFile;
        "text/xml" = cfg.desktopFile;
        "application/xhtml+xml" = cfg.desktopFile;
        "application/xml" = cfg.desktopFile;
        "application/pdf" = cfg.desktopFile;
        "x-scheme-handler/http" = cfg.desktopFile;
        "x-scheme-handler/https" = cfg.desktopFile;
        "x-scheme-handler/about" = cfg.desktopFile;
        "x-scheme-handler/unknown" = cfg.desktopFile;
      };
    };
  };
}
