{
  lib,
  fetchFromGitHub,
  luau,
  noctalia,
  patch,
  runCommand,
}:

let
  source = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "official-plugins";
    # Public upstream revision and content checksum.
    rev = "dc04fdda0383196ff7cc88dc33be77e36761609c"; # pragma: allowlist secret
    hash = "sha256-h/PnhllfPAi+QTvLa7Sf+Yj84KGcRI2I4F2gAIazA4A="; # pragma: allowlist secret
  };
in
runCommand "noctalia-wallhaven-sfw-1.2.0"
  {
    nativeBuildInputs = [
      luau
      noctalia
      patch
    ];
    meta = {
      description = "Wallhaven browser restricted to SFW search results";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    cp -R ${source}/wallhaven plugin
    chmod -R u+w plugin
    cd plugin
    patch -p1 < ${./sfw-only.patch}

    cat ${./test.luau} panel.luau > ../test.luau
    echo 'testSafeSearch()' >> ../test.luau
    luau ../test.luau
    luau-compile panel.luau >/dev/null
    noctalia plugins lint .
    cp -R . "$out"
  ''
