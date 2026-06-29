{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.lean;
in
{
  options.features.lean = {
    enable = lib.mkEnableOption "Lean theorem prover developer tooling";

    package = lib.mkOption {
      type = lib.types.package;
      default = pkgs.elan;
      defaultText = lib.literalExpression "pkgs.elan";
      description = "Lean toolchain manager package to install.";
    };

    lean4.enable = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether to install the pinned nixpkgs Lean 4 package alongside elan.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.package
    ]
    ++ lib.optional cfg.lean4.enable pkgs.lean4;
  };
}
