{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeFeatures.shell;
in

{
  imports = [
    ./completions.nix
  ];

  options.homeFeatures.shell.enable = lib.mkEnableOption "zsh shell experience";

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      eza
      fd
      jq
      ripgrep
    ];

    programs.zsh = {
      enable = true;
      autocd = true;
      enableCompletion = true;
      autosuggestion.enable = true;
      syntaxHighlighting.enable = true;

      history = {
        size = 50000;
        save = 50000;
        path = "${config.xdg.dataHome}/zsh/history";
        ignoreDups = true;
        ignoreSpace = true;
        share = true;
      };

      shellAliases = {
        c = "clear";
        grep = "grep --color=auto";
        la = "eza -la --group-directories-first";
        ll = "eza -lh --group-directories-first";
        ls = "eza --group-directories-first";
        nixswitch = "sudo nixos-rebuild switch --flake ~/projects/personal/nixos-config#desktop";
        nixbuild = "sudo nixos-rebuild build --flake ~/projects/personal/nixos-config#desktop";
        rebuild = "nixswitch";
        ga = "git add";
        gc = "git commit";
        gd = "git diff";
        gs = "git status --short";
      };
    };

    programs.fzf = {
      enable = true;
      enableZshIntegration = true;
    };

    programs.zoxide = {
      enable = true;
      enableZshIntegration = true;
    };

    programs.direnv = {
      enable = true;
      nix-direnv.enable = true;
    };
  };
}
