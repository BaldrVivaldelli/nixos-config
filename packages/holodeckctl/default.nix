{
  lib,
  awscli2,
  gh,
  glab,
  holodeck,
  makeWrapper,
  python3Packages,
  defaultRepoPath ? null,
}:

python3Packages.buildPythonApplication {
  pname = "holodeckctl";
  version = "0.2.0";
  pyproject = true;

  src = ./.;

  build-system = [ python3Packages.setuptools ];
  nativeBuildInputs = [ makeWrapper ];

  doCheck = true;
  checkPhase = ''
    runHook preCheck
    python -m unittest discover -s tests -v
    runHook postCheck
  '';

  pythonImportsCheck = [ "holodeckctl" ];

  postFixup = ''
    wrapProgram "$out/bin/holodeckctl" \
      --prefix PATH : ${
        lib.makeBinPath [
          awscli2
          gh
          glab
          holodeck
        ]
      } \
      ${lib.optionalString (
        defaultRepoPath != null
      ) "--set-default HOLODECK_REPO ${lib.escapeShellArg defaultRepoPath}"}
  '';

  meta = {
    description = "Safe bridge between Noctalia preferences and Holodeck";
    license = lib.licenses.mit;
    mainProgram = "holodeckctl";
    platforms = lib.platforms.linux;
  };
}
