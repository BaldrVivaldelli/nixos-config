{
  config,
  lib,
  pkgs,
  ...
}:

let
  cfg = config.homeFeatures.aws;

  zshWords = values: lib.concatMapStringsSep " " lib.escapeShellArg values;

  mkWordCompletion = command: label: values: ''
    #compdef ${command}

    _arguments \
      '*:${label}:(${zshWords values})'
  '';
in
{
  options.homeFeatures.aws = {
    enable = lib.mkEnableOption "AWS CLI and shell helpers";

    profiles = lib.mkOption {
      type = lib.types.listOf lib.types.str;
      default = [ ];
      description = "Non-secret AWS profile names for zsh completion.";
      example = [
        "personal"
        "work"
      ];
    };
  };

  config = lib.mkIf cfg.enable {
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

    programs.zsh.siteFunctions = {
      _awslogin = mkWordCompletion "awslogin" "AWS profile" cfg.profiles;
      _awscxt = mkWordCompletion "awscxt" "AWS profile" cfg.profiles;
    };
  };
}
