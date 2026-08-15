{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.rust;
in
{
  options.features.rust = {
    enable = lib.mkEnableOption "Rust developer tooling";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.rustc;
      defaultText = lib.literalExpression "pkgs.rustc";
      description = "Rust compiler package to install.";
    };

    cargo.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install Cargo alongside Rust.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ cfg.package ] ++ lib.optional cfg.cargo.enable pkgs.cargo;
  };
}
