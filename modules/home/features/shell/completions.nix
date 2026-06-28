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
      _windowsvm = mkSubcommandCompletion "windowsvm" windowsvmCommands [ ];
      _holodeck = mkSubcommandCompletion "holodeck" holodeckCommands [
        "2:provider:(${zshWords providers})"
      ];
    };
  };
}
