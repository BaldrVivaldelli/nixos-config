{
  lib,
  writeShellApplication,
  writeShellScriptBin,
  coreutils,
  xdg-utils,
  gh,
  git,
  glab,
  gnupg,
  openssh,
  python3,
  coreSource,
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

  # GitHub CLI launches the command from GH_BROWSER and otherwise lets the
  # graphical browser inherit Holodeck's terminal. Chromium then prints its
  # own diagnostic messages into the interactive authentication flow.
  # This small launcher detaches xdg-open and sends all browser output to
  # /dev/null while preserving the normal browser-based login.
  quietBrowser = writeShellScriptBin "holodeck-open-browser" ''
    set -eu

    url="''${1:-}"
    if [ -z "$url" ]; then
      exit 1
    fi

    ${coreutils}/bin/nohup ${xdg-utils}/bin/xdg-open "$url" \
      </dev/null >/dev/null 2>&1 &
  '';
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
    quietBrowser
  ];

  text = ''
    export HOLODECK_DEFAULT_GITHUB_HOST=${lib.escapeShellArg githubHost}
    export HOLODECK_DEFAULT_GITLAB_HOST=${lib.escapeShellArg gitlabHost}
    export HOLODECK_DEFAULT_PERSONAL_DIR=${shellPathDefault personalProjectsDir}
    export HOLODECK_DEFAULT_WORK_DIR=${shellPathDefault workProjectsDir}
    export PYTHONPATH=${coreSource}''${PYTHONPATH:+:$PYTHONPATH}

    # GH_BROWSER has precedence over BROWSER and only affects GitHub CLI
    # processes started by Holodeck. It does not change the user's default
    # browser outside this command.
    export GH_BROWSER=${quietBrowser}/bin/holodeck-open-browser

    exec python3 -m holodeck "$@"
  '';
}
