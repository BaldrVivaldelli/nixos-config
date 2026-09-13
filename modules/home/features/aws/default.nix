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
      _aws_remember_profile() (
        local state_dir="''${XDG_STATE_HOME:-$HOME/.local/state}/aws"
        local temporary_file

        umask 077
        mkdir -p -- "$state_dir" || return
        temporary_file="$(mktemp "$state_dir/last-profile.XXXXXX")" || return
        if ! printf '%s\n' "$1" > "$temporary_file" ||
           ! mv -f -- "$temporary_file" "$state_dir/last-profile"; then
          rm -f -- "$temporary_file"
          return 1
        fi
      )

      awslogin() {
        local profile="''${1:-''${AWS_PROFILE:-''${AWS_DEFAULT_PROFILE:-}}}"
        local state_file="''${XDG_STATE_HOME:-$HOME/.local/state}/aws/last-profile"

        if [ -z "$profile" ] && [ -r "$state_file" ]; then
          IFS= read -r profile < "$state_file"
        fi

        if [ -z "$profile" ]; then
          awscxt || return
          profile="$AWS_PROFILE"
        fi

        aws sso login --profile "$profile" || return
        _aws_remember_profile "$profile" || return
        export AWS_PROFILE="$profile"
        export AWS_DEFAULT_PROFILE="$profile"
      }

      awscxt() {
        setopt localoptions pipefail
        local profile

        profile="$(aws configure list-profiles | sort | fzf --height 40% --reverse --prompt='AWS profile> ')" || return

        if [ -z "$profile" ]; then
          return 1
        fi

        _aws_remember_profile "$profile" || return
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
