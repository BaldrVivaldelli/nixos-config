{ pkgs, ... }:

{
  home.packages = with pkgs; [
    awscli2
  ];

  programs.zsh.shellAliases = {
    awsprofiles = "aws configure list-profiles";
  };

  programs.zsh.initContent = ''
    awslogin() {
      local profile="''${1:-''${AWS_PROFILE:-}}"

      if [ -n "$profile" ]; then
        aws sso login --profile "$profile"
      else
        aws sso login
      fi
    }

    awscxt() {
      local profile

      profile="$(aws configure list-profiles | sort | fzf --height 40% --reverse --prompt='AWS profile> ')" || return

      if [ -z "$profile" ]; then
        return 1
      fi

      export AWS_PROFILE="$profile"
      export AWS_DEFAULT_PROFILE="$profile"
      echo "AWS_PROFILE=$AWS_PROFILE"
    }

    awswho() {
      aws sts get-caller-identity "$@"
    }
  '';
}

