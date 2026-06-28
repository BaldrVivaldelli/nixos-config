{ config, lib, pkgs, ... }:

let
  cfg = config.features.holodeck;

  shellPathDefault = value:
    if value == "$HOME" || value == "~" then
      ''"$HOME"''
    else if lib.hasPrefix "$HOME/" value then
      ''"$HOME/${lib.removePrefix "$HOME/" value}"''
    else if lib.hasPrefix "~/" value then
      ''"$HOME/${lib.removePrefix "~/" value}"''
    else
      lib.escapeShellArg value;

  holodeckCommand = pkgs.writeShellApplication {
    name = "holodeck";
    runtimeInputs = with pkgs; [
      bash
      coreutils
      gawk
      gh
      git
      glab
      gnugrep
      gnupg
      gnused
      openssh
      xdg-utils
    ];
    text = ''
      export HOLODECK_DEFAULT_GITHUB_HOST=${lib.escapeShellArg cfg.githubHost}
      export HOLODECK_DEFAULT_GITLAB_HOST=${lib.escapeShellArg cfg.gitlabHost}
      export HOLODECK_DEFAULT_PERSONAL_DIR=${shellPathDefault cfg.personalProjectsDir}
      export HOLODECK_DEFAULT_WORK_DIR=${shellPathDefault cfg.workProjectsDir}

    '' + builtins.readFile ./holodeck.sh;
  };
in
{
  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ holodeckCommand ];
  };
}
