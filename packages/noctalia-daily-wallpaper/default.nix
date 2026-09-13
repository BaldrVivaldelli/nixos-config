{
  lib,
  fetchFromGitHub,
  luau,
  noctalia,
  patch,
  python3,
  runCommand,
}:

let
  source = fetchFromGitHub {
    owner = "noctalia-dev";
    repo = "community-plugins";
    # Public upstream revision and content checksum.
    rev = "6d9bbf27632c8b5c75b3fe78364906bce81cf31f"; # pragma: allowlist secret
    hash = "sha256-OloRmCwNWbK94TM8iYaeID6Agdyl03UYnctdCTXFiOw="; # pragma: allowlist secret
  };
in
runCommand "noctalia-daily-wallpaper-1.1.0"
  {
    nativeBuildInputs = [
      luau
      noctalia
      patch
      python3
    ];
    meta = {
      description = "Bing and NASA editorial wallpapers with manual application";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    cp -R ${source}/daily-wallpaper plugin
    chmod -R u+w plugin
    cd plugin
    patch -p1 < ${./manual-feeds.patch}
    cp ${./panel.luau} panel.luau
    python ${./translations.py}

    cat ${./test.luau} daily_wallpaper.luau > ../service-test.luau
    echo 'testDailyService()' >> ../service-test.luau
    luau ../service-test.luau
    cat ${./panel-test.luau} panel.luau > ../panel-test.luau
    echo 'testDailyPanel()' >> ../panel-test.luau
    luau ../panel-test.luau
    luau-compile daily_wallpaper.luau >/dev/null
    luau-compile panel.luau >/dev/null
    noctalia plugins lint .
    cp -R . "$out"
  ''
