{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.git;
in
{
  options.features.git = {
    enable = lib.mkEnableOption "Git developer tooling";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.git;
      defaultText = lib.literalExpression "pkgs.git";
      description = "Git package to install.";
    };

    lfs.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install Git LFS.";
    };

    delta.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install delta for rich diffs.";
    };

    lazygit.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install lazygit.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optional cfg.lfs.enable pkgs.git-lfs
    ++ lib.optional cfg.delta.enable pkgs.delta
    ++ lib.optional cfg.lazygit.enable pkgs.lazygit;
  };
}
