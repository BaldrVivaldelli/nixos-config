{ config, lib, pkgs, ... }:

let
  cfg = config.features.vscodium;
in
{
  options.features.vscodium = {
    enable = lib.mkEnableOption "VSCodium editor";

    defaultEditor = lib.mkEnableOption "VSCodium as the default editor";
  };

  config = lib.mkIf cfg.enable {
    programs.vscode = {
      enable = true;
      package = pkgs.vscodium;
      defaultEditor = cfg.defaultEditor;
      extensions =
        pkgs.vscode-utils.extensionsFromVscodeMarketplace
          (builtins.fromJSON (builtins.readFile ./extensions.json));
    };
  };
}
