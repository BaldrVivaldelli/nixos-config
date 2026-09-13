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

La interfaz es el panel Luau nativo `holodeck/control:control` de Noctalia.
El icono `holodeck/control:config` de la barra abre ese mismo panel; no abre un
navegador ni una aplicación web. Se conserva la entrada del launcher.

El inicio presenta **Trabajo** y **Equipo** con la misma jerarquía. Trabajo
incluye AWS, Windows, GitHub y GitLab. Equipo incluye apariencia, alcance de la
configuración, aplicación y tamaño de Windows. Una búsqueda filtra todas las
tareas; las mismas acciones se encuentran desplazándose por el inicio.

El presupuesto de navegación se cuenta desde el panel abierto:

| Tarea | Recorrido | Clics |
| --- | --- | --- |
| Windows configurado | Abrir Windows | 1 |
| AWS con perfil recordado | Entrar a AWS | 1 |
| Seleccionar perfil AWS | Cambiar perfil → elegir perfil | 2 |
| Alias de una cuenta | Editar alias → elegir cuenta → guardar | 3 |
| Apariencia o alcance | Abrir tarea → elegir opción → confirmar y aplicar | 3 |
| Aplicar configuración guardada | Aplicar cambios → confirmar | 2 |
| Tamaño de Windows | Ventana de Windows → elegir tamaño | 2 |
| Reemplazar contraseña o recrear Windows | Abrir tarea → confirmar | 2 |

Escritura, edición de campos y autenticación externa se consideran trabajo
adicional. Las operaciones interactivas mantienen su terminal visible.

AWS usa el mismo archivo `~/.local/state/aws/last-profile` que los helpers de
Zsh (`$XDG_STATE_HOME/aws/last-profile` si está definido). La selección desde el
panel se entrega como JSON a `aws-profile-select`, que valida el nombre contra
los perfiles existentes y lo guarda de forma atómica. `aws-login` reutiliza
el perfil del entorno o el último guardado. No cambia variables de terminales
que ya estaban abiertas. Sin selección, el panel ofrece elegir un perfil.

Renovar la sesión y sincronizar cuentas son acciones separadas. Sincronizar
conserva el descubrimiento de cuentas/roles y las preferencias de alias y
regiones. El editor permite buscar una cuenta y editarla individualmente;
una acción aparte aplica los alias recomendados a todas las cuentas.

La tarea de apariencia o alcance conserva las elecciones en memoria hasta
**Confirmar y aplicar**. Ese botón ejecuta uno de cinco comandos fijos
`apply-change`: el backend adquiere el lock, valida, guarda la opción elegida
y ejecuta el instalador. La UI no requiere guardar y generar un plan por
separado. Cancelar antes de confirmar no modifica el IR. Si el build falla,
la elección queda guardada para corregir el problema y volver a aplicar.

Windows conserva el onboarding de usuario y contraseña, su transporte privado
y el acceso RDP automático. Reemplazar la contraseña y recrear la VM son tareas
independientes con sus efectos visibles antes de confirmar. Recrear exige
escribir exactamente `WIPE`; detener Windows también pide confirmación.
Una instalación existente se reconoce por su disco y los marcadores de Windows,
aunque todavía no tenga el archivo privado de credenciales. En Niri, abrir
Windows activa su ventana RDP local si ya existe. Los fallos del proceso vuelven
al formulario con el error visible y la contraseña vacía. Las consultas a GitLab
tienen un límite de tiempo para que no bloqueen las demás tareas del panel.

El estado de configuración se refresca cada ocho segundos mientras el inicio
está abierto. No se interpreta la apertura de una terminal como éxito de la
operación: los resultados interactivos siguen visibles allí. Los formularios
conservan su estado mientras se editan.

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
holodeckctl apply-change theme-light
holodeckctl aws-profile-select --json
holodeckctl aws-aliases-apply --json
holodeckctl action holodeck-setup
holodeckctl action github-setup
holodeckctl action gitlab-setup
holodeckctl action aws-sync
holodeckctl action windows-up
holodeckctl action windows-unlock
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
