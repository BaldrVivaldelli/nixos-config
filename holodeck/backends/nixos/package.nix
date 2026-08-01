{
  lib,
  writeShellApplication,
  coreutils,
  git,
  nix,
  python3,
  sudo,
  defaultWslUser ? "nixos",
  defaultWslHostName ? "nixos-wsl",
  defaultRepoPath ? "/home/${defaultWslUser}/projects/personal/nixos-config",
}:

writeShellApplication {
  name = "holodeck-system-nixos";

  runtimeInputs = [
    coreutils
    git
    nix
    python3
    sudo
  ];

  text = ''
    export HOLODECK_NIXOS_WSL_USER=${lib.escapeShellArg defaultWslUser}
    export HOLODECK_NIXOS_WSL_HOST_NAME=${lib.escapeShellArg defaultWslHostName}
    export HOLODECK_NIXOS_REPO_PATH=${lib.escapeShellArg defaultRepoPath}
    export PYTHONPATH=${../../core}:${./.}''${PYTHONPATH:+:$PYTHONPATH}

    exec python3 -m holodeck_system_nixos "$@"
  '';
}
