{
  lib,
  writeShellApplication,
  coreutils,
  findutils,
  gh,
  git,
  glab,
  gnupg,
  nix,
  openssh,
  python3,
  sudo,
  util-linux,
  xdg-utils,
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
    coreutils
    findutils
    gh
    git
    glab
    gnupg
    nix
    openssh
    python3
    sudo
    util-linux
    xdg-utils
  ];

  text = ''
    export HOLODECK_DEFAULT_GITHUB_HOST=${lib.escapeShellArg githubHost}
    export HOLODECK_DEFAULT_GITLAB_HOST=${lib.escapeShellArg gitlabHost}
    export HOLODECK_DEFAULT_PERSONAL_DIR=${shellPathDefault personalProjectsDir}
    export HOLODECK_DEFAULT_WORK_DIR=${shellPathDefault workProjectsDir}
    export PYTHONPATH=${./app}''${PYTHONPATH:+:$PYTHONPATH}

    exec python3 -m holodeck "$@"
  '';
}
