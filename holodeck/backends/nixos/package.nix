{
  writeShellApplication,
  git,
  nix,
  python3,
  sudo,
  util-linux,
}:

writeShellApplication {
  name = "holodeck-system-nixos";

  runtimeInputs = [
    git
    nix
    python3
    sudo
    util-linux
  ];

  text = ''
    export PYTHONPATH=${../../core}:${./.}''${PYTHONPATH:+:$PYTHONPATH}

    exec python3 -m holodeck_system_nixos "$@"
  '';
}
