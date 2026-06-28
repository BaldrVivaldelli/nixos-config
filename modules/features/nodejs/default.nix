{ config, lib, pkgs, ... }:

let
  cfg = config.features.nodejs;
in
{
  options.features.nodejs = {
    enable = lib.mkEnableOption "Node.js developer tooling";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.nodejs;
      defaultText = lib.literalExpression "pkgs.nodejs";
      description = "Node.js package to install. This includes npm and npx.";
    };

    pnpm.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to install pnpm alongside Node.js.";
    };

    yarn.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to install Yarn alongside Node.js.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages =
      [ cfg.package ]
      ++ lib.optional cfg.pnpm.enable pkgs.pnpm
      ++ lib.optional cfg.yarn.enable pkgs.yarn;
  };
}

