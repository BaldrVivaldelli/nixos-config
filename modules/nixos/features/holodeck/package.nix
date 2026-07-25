{
  lib,
  writeShellApplication,
  gh,
  git,
  glab,
  gnupg,
  openssh,
  python3,
  coreSource ? ../../../../holodeck/core,
  githubHost ? "github.com",
  gitlabHost ? "gitlab.com",
  personalProjectsDir ? "$HOME/projects/personal",
  workProjectsDir ? "$HOME/projects/work",
}:

let
  shellPathDefault =
    value:
    if value == "$HOME" || value == "~" then
      ''"$HOME"''
    else if lib.hasPrefix "$HOME/" value then
      ''"$HOME/${lib.removePrefix "$HOME/" value}"''
    else if lib.hasPrefix "~/" value then
      ''"$HOME/${lib.removePrefix "~/" value}"''
    else
      lib.escapeShellArg value;
in
writeShellApplication {
  name = "holodeck";

  runtimeInputs = [
    gh
    git
    glab
    gnupg
    openssh
    python3
  ];

  text = ''
    export HOLODECK_DEFAULT_GITHUB_HOST=${lib.escapeShellArg githubHost}
    export HOLODECK_DEFAULT_GITLAB_HOST=${lib.escapeShellArg gitlabHost}
    export HOLODECK_DEFAULT_PERSONAL_DIR=${shellPathDefault personalProjectsDir}
    export HOLODECK_DEFAULT_WORK_DIR=${shellPathDefault workProjectsDir}
    export PYTHONPATH=${coreSource}''${PYTHONPATH:+:$PYTHONPATH}

    exec python3 -m holodeck "$@"
  '';
}
