{
  lib,
  luau,
  noctalia,
  holodeckctl,
  runCommand,
}:

runCommand "holodeck-noctalia-plugin-0.4.6"
  {
    nativeBuildInputs = [
      luau
      noctalia
    ];

    meta = {
      description = "Noctalia frontend for the declarative Holodeck IR";
      license = lib.licenses.mit;
      platforms = lib.platforms.linux;
    };
  }
  ''
    mkdir -p "$out"
    cp -R ${../../plugins/noctalia/holodeck-control}/. "$out/"
    chmod -R u+w "$out"

    substituteInPlace "$out/panel.luau" \
      --replace-fail '@holodeckctl@' '${lib.getExe holodeckctl}'

    # Keep palette roles compatible with the pinned Noctalia beta. Its runtime
    # logs and skips unknown roles instead of making plugin lint fail.
    if grep -Eq '"(primary|secondary|tertiary|error)_container(/[^" ]+)?"|"on_(primary|secondary|tertiary|error)_container"' "$out"/*.luau; then
      echo "unsupported Noctalia palette container role in Luau source" >&2
      exit 1
    fi

    luau-compile "$out/panel.luau" >/dev/null
    luau-compile "$out/widget.luau" >/dev/null
    noctalia plugins lint "$out"
  ''
