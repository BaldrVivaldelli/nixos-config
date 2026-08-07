# Holodeck Control

`Holodeck Control` es un plugin de Noctalia v5 que permite seleccionar una parte
acotada de la configuración sin trasladar lógica del sistema a Luau.

```text
panel Luau
  └── holodeckctl
      ├── holodeck.local.json → Nix → Home Manager / NixOS
      ├── holodeck → GitHub / GitLab
      ├── aws → login SSO y sincronización de cuentas/roles
      └── windowsvm → Dockurr / RDP / visor web
```

## Instalación y apertura

No tiene un instalador separado. El perfil `developer` lo incorpora mediante
Home Manager, por lo que queda instalado con cualquiera de estos flujos:

```bash
./install.sh home-manager
./install.sh existing-nixos
```

Después se abre desde `Mod+Space` buscando `Holodeck Control`, o directamente:

```bash
noctalia msg panel-toggle holodeck/control:control
```

El icono propio representa una cámara de simulación holográfica. La versión
completa aparece en el launcher, los README y el encabezado del panel; una
versión reducida conserva sólo la cámara y el destello para la navegación
compacta. La barra usa el glifo nativo `cube-spark`, que toma el color
`on_surface` del tema activo y mantiene la misma escala que sus vecinos.

Home Manager agrega automáticamente `holodeck/control:config` al extremo
derecho de la barra principal, antes de Control Center y sesión. El widget sólo
muestra el glifo temático; su tooltip explica la acción y un click abre el panel.

## IR v2

El backend crea `holodeck.local.json` sólo cuando el usuario guarda por primera
vez. Si no existe, `status` muestra defaults seguros sin escribir nada.

```json
{
  "appearance": {
    "theme": {
      "builtin": "Catppuccin",
      "mode": "dark"
    }
  },
  "deployment": {
    "target": "home-manager"
  },
  "desktop": {
    "compositor": "niri",
    "shell": "noctalia"
  },
  "integrations": {
    "windows": {
      "rdp": {
        "displayMode": "half"
      }
    }
  },
  "schemaVersion": 2
}
```

El frontend actual permite elegir:

- `deployment.target`: `home-manager` o `existing-nixos`;
- `appearance.theme.mode`: `dark` o `light`;
- `integrations.windows.rdp.displayMode`: `half` o `fullscreen`.

Niri y Noctalia son los únicos valores aceptados por el schema v2 para
compositor y shell. Los archivos v1 se migran automáticamente con media pantalla
como valor seguro. Extender el contrato requiere cambiar en conjunto el modelo
Python, la validación Nix, los tests y la UI.

## Navegación e integraciones

La interfaz usa los controles declarativos nativos de Noctalia y una barra
lateral compacta, equivalente al modo compacto del Control Center, para
organizar el flujo en tres vistas:

- **Resumen**: estado del IR y lectura rápida de las cuatro integraciones;
- **Sistema**: target, apariencia, guardado del IR, plan y confirmación;
- **Integraciones**: selector compacto y detalle de un proveedor por vez.

La vista de integraciones reúne:

- **GitHub**: perfiles detectados y configuración completa de auth, SSH y Git;
- **GitLab**: un único botón acepta la URL de la instancia o de un grupo;
  después extrae el host y se limita a reutilizar o abrir OAuth web/SSO, sin
  crear perfiles, claves SSH, routing Git ni un host hardcodeado;
- **AWS**: un único botón abre el login SSO y descubre cada combinación de
  cuenta y rol asignada; la URL se lee de una sesión local existente o se
  solicita en la primera ejecución, nunca desde el inventario. Cada asignación
  genera automáticamente un perfil en `us-east-1` y otro en `us-east-2`, con
  sufijos `use1` y `use2`. El editor permite escribir un alias, aceptar una
  recomendación, conservar ambas regiones, dejar sólo una o agregar otras
  separadas por coma; las elecciones sobreviven a las resincronizaciones;
- **Windows VM**: disponibilidad de `windowsvm`, inicio, estado, RDP, visor web,
  logs y detención.

`Configurar todo` reutiliza el wizard existente de `holodeck` para configurar
GitHub y autenticar GitLab y, al terminar, siempre ofrece configurar o
resincronizar AWS SSO;
`Diagnóstico` ejecuta `holodeck doctor`. Las operaciones interactivas se abren en una
terminal y al finalizar se puede usar la recarga del encabezado para releer el
estado. **RDP** y **Web** son lanzadores gráficos: se ejecutan directamente sin
crear una terminal efímera; RDP usa el cliente SDL nativo en Wayland. Los
botones usan tamaños semánticos de Noctalia, la acción principal de cada vista
queda destacada y **Detener** usa explícitamente el estilo destructivo.

Windows aparece disponible después de aplicar `./install.sh` con la opción 1,
porque `windowsvm` pertenece al perfil del sistema NixOS. GitHub, GitLab y AWS
pertenecen al perfil de usuario instalado por Home Manager.

## Backend

Los comandos públicos son:

```bash
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
holodeckctl action github-setup
holodeckctl action gitlab-setup
holodeckctl action aws-sync
holodeckctl action windows-up
```

`plan` valida el archivo y muestra el `argv` literal. `apply` mantiene el lock
del IR y delega, sin `shell=True` ni `sudo` propio, en:

```text
./install.sh home-manager
./install.sh existing-nixos
```

El segundo target puede pedir `sudo` dentro del flujo NixOS ya existente. El
plugin siempre abre `apply` en una terminal, por lo que el build, los errores y
la autenticación permanecen visibles.

## Límites de seguridad

- Luau sólo puede elegir comandos y valores de allowlists estáticas.
- Los nombres de perfiles se muestran como metadata, pero emails, claves,
  fingerprints, tokens y credenciales nunca forman parte del JSON de estado.
- El plugin no escribe el IR ni genera expresiones Nix. Para guardar alias y
  regiones AWS escribe únicamente una solicitud transitoria en su directorio
  de estado; `holodeckctl` la valida, aplica y elimina.
- El backend rechaza schemas futuros, claves desconocidas y enums inválidos.
- Las escrituras usan archivo temporal, `fsync`, reemplazo atómico y lock.
- Nix vuelve a validar el IR antes de construir.
- El plugin ignora el `argv` informado por `plan`; `apply` usa un comando fijo
  empaquetado con una ruta inmutable del Nix store.
- Las integraciones resuelven el ejecutable y usan listas `argv` con
  `shell=False`.
- AWS CLI conserva el token bajo `~/.aws/sso/cache`; Holodeck sólo lo mantiene
  en memoria mientras pagina las APIs SSO y nunca lo devuelve al frontend.
- La sincronización AWS reemplaza únicamente un bloque delimitado y generado
  por Holodeck en `~/.aws/config`; los perfiles externos quedan intactos.
- Los alias y regiones persistentes viven en
  `~/.config/holodeck/aws-aliases.json`, fuera del repositorio, y usan claves
  opacas estables en lugar de nombres o IDs de cuenta.

`holodeck.local.json` y `holodeck.local.json.lock` están ignorados por Git. Los
scripts evalúan explícitamente `path:$repo` para que ese estado local participe
del build sin publicarse en el repositorio.
