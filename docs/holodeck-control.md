# Holodeck Control

`Holodeck Control` es un plugin de Noctalia v5 que permite seleccionar una parte
acotada de la configuración sin trasladar lógica del sistema a Luau.

```text
panel Luau
  └── holodeckctl
      ├── holodeck.local.json → Nix → Home Manager / NixOS
      ├── holodeck → GitHub / GitLab
      ├── aws → perfiles SSO e identidad
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

## IR v1

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
  "schemaVersion": 1
}
```

El frontend actual permite elegir:

- `deployment.target`: `home-manager` o `existing-nixos`;
- `appearance.theme.mode`: `dark` o `light`.

Niri y Noctalia son los únicos valores aceptados por el schema v1 para
compositor y shell. Extenderlos requiere cambiar en conjunto el modelo Python,
la validación Nix, los tests y la UI.

## Navegación e integraciones

La interfaz usa los controles declarativos nativos de Noctalia y una barra
lateral compacta, equivalente al modo compacto del Control Center, para
organizar el flujo en tres vistas:

- **Resumen**: estado del IR y lectura rápida de las cuatro integraciones;
- **Sistema**: target, apariencia, guardado del IR, plan y confirmación;
- **Integraciones**: selector compacto y detalle de un proveedor por vez.

La vista de integraciones reúne:

- **GitHub**: perfiles detectados y configuración completa de auth, SSH y Git;
- **GitLab**: perfiles detectados y configuración independiente de auth/SSH/Git;
- **AWS**: nombres de perfiles de `~/.aws/config`, configuración SSO, login e
  identidad activa;
- **Windows VM**: disponibilidad de `windowsvm`, inicio, estado, RDP, visor web,
  logs y detención.

`Configurar todo` reutiliza el wizard existente de `holodeck`; `Diagnóstico`
ejecuta `holodeck doctor`. Todas las operaciones interactivas se abren en una
terminal y al finalizar se puede usar la recarga del encabezado para releer el
estado. Los botones usan tamaños semánticos de Noctalia, la acción principal de
cada vista queda destacada y **Detener** usa explícitamente el estilo
destructivo.

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
holodeckctl plan --json
holodeckctl apply
holodeckctl action holodeck-setup
holodeckctl action github-setup
holodeckctl action gitlab-setup
holodeckctl action aws-configure
holodeckctl action aws-login
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
- El plugin no escribe JSON ni genera expresiones Nix.
- El backend rechaza schemas futuros, claves desconocidas y enums inválidos.
- Las escrituras usan archivo temporal, `fsync`, reemplazo atómico y lock.
- Nix vuelve a validar el IR antes de construir.
- El plugin ignora el `argv` informado por `plan`; `apply` usa un comando fijo
  empaquetado con una ruta inmutable del Nix store.
- Las integraciones resuelven el ejecutable y usan listas `argv` con
  `shell=False`; los perfiles AWS sólo pueden elegirse de la lista detectada.

`holodeck.local.json` y `holodeck.local.json.lock` están ignorados por Git. Los
scripts evalúan explícitamente `path:$repo` para que ese estado local participe
del build sin publicarse en el repositorio.
