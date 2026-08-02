{ config, lib, ... }:

let
  cfg = config.homeFeatures.shell;
  escape = lib.escapeShellArg;

  zshWords = values: lib.concatMapStringsSep " " escape values;

  mkSubcommandCompletion =
    command: commands: extraSpecs:
    let
      specs = [ "1:${command} command:(${zshWords commands})" ] ++ extraSpecs;
    in
    ''
      #compdef ${command}

      _arguments \
        ${lib.concatMapStringsSep " \\\n        " escape specs}
    '';

  windowsvmCommands = [
    "down"
    "help"
    "logs"
    "rdp"
    "remove"
    "rm"
    "start"
    "status"
    "stop"
    "up"
    "web"
  ];

  holodeckCommands = [
    "auth"
    "clean"
    "doctor"
    "github"
    "gitlab"
    "help"
    "login"
    "profile"
    "purge"
    "sanitize"
    "setup"
    "status"
  ];

  providers = [
    "github"
    "gitlab"
  ];

in
{
  config = lib.mkIf cfg.enable {
    programs.zsh.siteFunctions = {
      _windowsvm = ''
        #compdef windowsvm

        if (( CURRENT == 2 )); then
          _values "windowsvm command" ${zshWords windowsvmCommands}
          return
        fi

        case "$words[2]" in
          up|rdp)
            _values "RDP display mode" half fullscreen
            ;;
        esac
      '';
      _holodeck = ''
        #compdef holodeck

        if (( CURRENT == 2 )); then
          _values "holodeck command" ${zshWords holodeckCommands}
          return
        fi

        case "$words[2]" in
          auth|login|profile)
            _values "provider" ${zshWords providers}
            ;;
        esac
      '';
    };
  };
}
