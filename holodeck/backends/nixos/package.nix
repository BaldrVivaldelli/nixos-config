{
  writeShellApplication,
  coreutils,
  git,
  nix,
  python3,
  sudo,
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
    export PYTHONPATH=${../../core}:${./.}''${PYTHONPATH:+:$PYTHONPATH}

    exec python3 -m holodeck_system_nixos "$@"
  '';
}
