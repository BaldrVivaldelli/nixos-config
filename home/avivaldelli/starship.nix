{ ... }:

{
  programs.starship = {
    enable = true;
    enableZshIntegration = true;
    settings = {
      add_newline = true;
      command_timeout = 1000;

      character = {
        success_symbol = "[>](bold green)";
        error_symbol = "[>](bold red)";
      };

      directory = {
        truncation_length = 3;
        truncate_to_repo = true;
      };

      git_branch.symbol = "git:";
      nix_shell.symbol = "nix:";
      nodejs.symbol = "node:";
      python.symbol = "py:";
      aws.symbol = "aws:";
    };
  };
}

