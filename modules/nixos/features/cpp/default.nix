{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.features.cpp;
in
{
  options.features.cpp = {
    enable = lib.mkEnableOption "C and C++ developer tooling";

    compiler = lib.mkOption {
      type = lib.types.package;
      default = pkgs.gcc;
      defaultText = lib.literalExpression "pkgs.gcc";
      description = "C and C++ compiler package to install.";
    };

    buildTools = lib.mkOption {
      type = lib.types.listOf lib.types.package;
      default = with pkgs; [
        binutils
        gnumake
        cmake
        ninja
        pkg-config
      ];
      defaultText = lib.literalExpression ''
        with pkgs; [ binutils gnumake cmake ninja pkg-config ]
      '';
      description = "Build and linking tools to install alongside the compiler.";
    };

    debugger.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install GDB.";
    };

    clangTools.enable = lib.mkOption {
      type = lib.types.bool;
      default = true;
      description = "Whether to install clangd, clang-format and related Clang tools.";
    };
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [
      cfg.compiler
    ]
    ++ cfg.buildTools
    ++ lib.optional cfg.debugger.enable pkgs.gdb
    ++ lib.optional cfg.clangTools.enable pkgs.clang-tools;
  };
}
