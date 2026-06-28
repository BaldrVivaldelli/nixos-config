{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.python;
in
{
  options.features.python = {
    enable = lib.mkEnableOption "Python developer tooling";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.python3;
      defaultText = lib.literalExpression "pkgs.python3";
      description = "Python interpreter package to install.";
    };

    uv.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install uv alongside Python.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ] ++ lib.optional cfg.uv.enable pkgs.uv;
  };
}
