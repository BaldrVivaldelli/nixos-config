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
  options.homeFeatures.shell = {
    enable = lib.mkEnableOption "zsh shell experience";

    repoPath = lib.mkOption {
      type = lib.types.str;
      default = "/home/avivaldelli/projects/personal/nixos-config";
      description = "Ruta del repositorio personal de Home Manager";
    };
  };

  config = lib.mkIf cfg.enable {
    home.packages = with pkgs; [
      eza
      fd
      jq
      ripgrep
    ];

    home.sessionVariables.SHELL = "${pkgs.zsh}/bin/zsh";

    # Home Manager cannot update the login shell in /etc/passwd by itself.
    # Redirect terminal sessions that still start Bash while leaving scripts,
    # `bash -c` and explicitly requested Bash sessions untouched.
    programs.bash = {
      enable = true;
      initExtra = ''
        if [[ $- == *i* && -z "''${BASH_EXECUTION_STRING:-}" && -z "''${HM_KEEP_BASH:-}" ]]; then
          exec ${pkgs.zsh}/bin/zsh
        fi
      '';
    };

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
        ga = "git add";
        gc = "git commit";
        gd = "git diff";
        gs = "git status --short";

        hmbuild = "${cfg.repoPath}/apply-home.sh build";
        hmswitch = "${cfg.repoPath}/apply-home.sh switch";
        hmverify = "${cfg.repoPath}/verify-user-only.sh";
        rebuild = "hmswitch";
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
