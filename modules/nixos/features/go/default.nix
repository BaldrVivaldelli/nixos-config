{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.go;
in
{
  options.features.go = {
    enable = lib.mkEnableOption "Go developer tooling";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.go;
      defaultText = lib.literalExpression "pkgs.go";
      description = "Go toolchain package to install.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ];
  };
}
