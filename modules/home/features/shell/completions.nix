{ lib, ... }:

let
  escape = lib.escapeShellArg;

  zshWords = values:
    lib.concatMapStringsSep " " escape values;

  mkSubcommandCompletion = command: commands: extraSpecs:
    let
      specs = [ "1:${command} command:(${zshWords commands})" ] ++ extraSpecs;
    in
    ''
      #compdef ${command}

      _arguments \
        ${lib.concatMapStringsSep " \\\n        " escape specs}
    '';

  mkWordCompletion = command: label: values: ''
    #compdef ${command}

    _arguments \
      '*:${label}:(${zshWords values})'
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

  awsProfiles = [
    # Add non-secret profile names here if you want zsh to complete them.
    # Example: "personal"
  ];
in
{
  programs.zsh.siteFunctions = {
    _windowsvm = mkSubcommandCompletion "windowsvm" windowsvmCommands [ ];
    _holodeck = mkSubcommandCompletion "holodeck" holodeckCommands [
      "2:provider:(${zshWords providers})"
    ];
    _awslogin = mkWordCompletion "awslogin" "AWS profile" awsProfiles;
    _awscxt = mkWordCompletion "awscxt" "AWS profile" awsProfiles;
  };
}

