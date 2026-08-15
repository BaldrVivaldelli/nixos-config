# holodeckctl

Puente estándar entre una UI (por ejemplo, un plugin de Noctalia) y la
configuración declarativa de este repositorio.

El comando administra `holodeck.local.json`, un IR local versionado. Luau sólo
expresa intención; este backend valida una allowlist y Nix sigue siendo quien
construye y activa el resultado.

```console
holodeckctl help
holodeckctl status --json
holodeckctl init
holodeckctl set deployment.target existing-nixos
holodeckctl set appearance.theme.mode light
holodeckctl set integrations.windows.rdp.displayMode fullscreen
holodeckctl plan --json
holodeckctl apply
holodeckctl aws-aliases-apply --json
holodeckctl action holodeck-setup
holodeckctl action holodeck-doctor
holodeckctl action github-setup
holodeckctl action gitlab-setup
holodeckctl action aws-sync
holodeckctl action windows-up
holodeckctl action windows-status
holodeckctl action windows-rdp
holodeckctl action windows-unlock
holodeckctl action windows-password-reset
holodeckctl action windows-wipe
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
`windowsvm`. Sólo expone perfiles GitHub, el host autenticado de GitLab,
cuenta/rol AWS, disponibilidad de comandos y, para Windows, si existe una
credencial segura, su username y la versión de resiliencia RDP. Nunca devuelve
la password. `action` acepta exclusivamente el enum documentado, resuelve el
ejecutable y usa `shell=False`; los flujos interactivos no aceptan `--json`.

`gitlab-setup` abre el flujo automático de Holodeck. Acepta la URL de la
instancia o de un grupo; Holodeck extrae el host y `glab` reutiliza una sesión
válida o abre OAuth web/SSO. El flujo termina al autenticar: no crea perfiles,
claves SSH ni configuración Git.

`aws-sync` concentra la integración con IAM Identity Center: configura o
reutiliza una sesión SSO, abre `aws sso login`, pagina todas las cuentas y roles
asignados y genera automáticamente dos perfiles por combinación: uno en
`us-east-1` y otro en `us-east-2`. Estas regiones cliente son una política de
Holodeck independiente de `sso_region`. Sólo reemplaza el bloque marcado en
`~/.aws/config`; cualquier sección externa se conserva. El access token se lee
del cache local de AWS CLI sólo durante el proceso y no se imprime ni se escribe
en los perfiles.

Cada nombre generado termina con la región cliente elegida, por ejemplo
`production-administratoraccess-use1` o `production-administratoraccess-use2`.
Después del descubrimiento, una sola asignación produce, por ejemplo,
`dp-prd-ro-use1` y `dp-prd-ro-use2`. Holodeck permite aplicar una recomendación
corta, guardar un alias personalizado, conservar ambas regiones, dejar sólo una
o agregar otras; cada región elegida genera un perfil independiente.

Los aliases y regiones se guardan fuera del repositorio en
`~/.config/holodeck/aws-aliases.json`, usando una clave opaca estable por
combinación de sesión, cuenta y rol. El comando interno
`aws-aliases-apply --json` consume el borrador fijo de Noctalia, valida ambas
preferencias y regenera únicamente el bloque administrado sin iniciar otro
login. El schema v2 se migra sin perder aliases y recibe automáticamente ambos
perfiles regionales.

La URL SSO no forma parte del inventario ni del paquete. Si todavía no existe
una sesión reutilizable en `~/.aws/config`, la primera sincronización la pide y
la guarda únicamente en ese archivo local. `sso_region` sólo localiza IAM
Identity Center: nunca se reutiliza como región cliente de los perfiles.

## IR v2

```json
{
  "appearance": {
    "theme": { "builtin": "Catppuccin", "mode": "dark" }
  },
  "deployment": { "target": "home-manager" },
  "desktop": { "compositor": "niri", "shell": "noctalia" },
  "integrations": {
    "windows": { "rdp": { "displayMode": "half" } }
  },
  "schemaVersion": 2
}
```

Los IR v1 se migran en memoria con `displayMode=half` y se escriben como v2 en
el siguiente `set`. El modo RDP sólo acepta `half` o `fullscreen`.

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
