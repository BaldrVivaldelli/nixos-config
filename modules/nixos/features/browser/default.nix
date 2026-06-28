{ config, lib, pkgs, ... }:

let
  cfg = config.features.browser;
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

    environment.systemPackages = [ cfg.package ];
  };
}
