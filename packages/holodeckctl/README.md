# holodeckctl

Puente estándar sin dependencias Python entre una UI (por ejemplo, un plugin de
Noctalia) y la configuración declarativa de este repositorio.

El comando administra `holodeck.local.json`, un IR local versionado. Luau sólo
expresa intención; este backend valida una allowlist y Nix sigue siendo quien
construye y activa el resultado.

```console
holodeckctl help
holodeckctl status --json
holodeckctl init
holodeckctl set deployment.target existing-nixos
holodeckctl set appearance.theme.mode light
holodeckctl plan --json
holodeckctl apply
holodeckctl action holodeck-setup
holodeckctl action holodeck-doctor
holodeckctl action github-setup
holodeckctl action gitlab-setup
holodeckctl action aws-configure
holodeckctl action aws-login
holodeckctl action aws-identity
holodeckctl action windows-up
holodeckctl action windows-status
holodeckctl action windows-rdp
holodeckctl action windows-web
holodeckctl action windows-logs
holodeckctl action windows-down
```

`--repo PATH` / `HOLODECK_REPO` seleccionan el repositorio.
`--ir PATH` / `HOLODECK_IR` seleccionan el IR. Una ruta de IR relativa se
resuelve contra el repositorio. Por defecto se usa `<repo>/holodeck.local.json`.

`plan` expone el `argv` literal que usará `apply`. `apply` nunca usa `shell=True`
ni agrega `sudo`: delega en `install.sh home-manager` o
`install.sh existing-nixos`. El segundo flujo informa `requiresElevation=true`
porque el instalador existente solicita elevación durante `nixos-rebuild`.

`status --json` agrega un resumen no sensible de GitHub, GitLab, AWS y
`windowsvm`. Sólo expone nombres de perfil, provider/host y disponibilidad de
comandos. `action` acepta exclusivamente el enum documentado, resuelve el
ejecutable y usa `shell=False`; los flujos interactivos no aceptan `--json`.

## IR v1

```json
{
  "appearance": {
    "theme": { "builtin": "Catppuccin", "mode": "dark" }
  },
  "deployment": { "target": "home-manager" },
  "desktop": { "compositor": "niri", "shell": "noctalia" },
  "schemaVersion": 1
}
```

Las escrituras son atómicas y `init`, `set` y `apply` comparten un lock
exclusivo. El lock evita que cambie el IR durante una aplicación.

## Desarrollo y paquete Nix

```console
PYTHONPATH=src python -m unittest discover -s tests -v
nix build --impure --expr 'let pkgs = import <nixpkgs> {}; in pkgs.callPackage ./default.nix {}'
```

La flake puede empaquetarlo con:

```nix
holodeck = pkgs.callPackage ./packages/holodeck {
  coreSource = ./holodeck/core;
};
holodeckctl = pkgs.callPackage ./packages/holodeckctl { inherit holodeck; };
```
