# Arquitectura

La flake expone Home Manager standalone, NixOS-WSL, dos comandos Holodeck y el
controlador declarativo del escritorio.

```text
inventory.nix
├── defaults portables
└── inventory.local.nix (detección local, ignorada por Git)
holodeck.local.json (intención del escritorio, ignorada por Git)
└── lib/holodeck-ir.nix (schema y validación)
flake.nix
├── homeConfigurations.default
│   └── home/default.nix
│       └── modules/home/profiles/<perfil>
├── nixosConfigurations.wsl
│   ├── nixos-wsl.nixosModules.default
│   ├── modules/parts.nix
│   │   ├── modules/home
│   │   └── modules/nixos/features
│   └── modules/hosts/wsl
├── nixosConfigurations.existing
│   ├── /etc/nixos/configuration.nix (sólo durante evaluación impura)
│   └── modules/nixos/profiles/niri-desktop
├── apps.holodeck
│   └── packages/holodeck
│       └── holodeck/core
├── apps.holodeck-system-nixos
│   └── holodeck/backends/nixos
├── apps.holodeckctl
│   └── packages/holodeckctl
└── packages.holodeck-noctalia-plugin
    └── plugins/noctalia/holodeck-control
```

## Home Manager

`inventory.nix` combina los defaults versionados con `inventory.local.nix`.
`lib/inventory.nix` normaliza el resultado y deriva home, descripción, perfil,
ruta del repositorio y metadatos del host. `homeConfigurations.default` apunta al usuario lógico
elegido por `defaultHomeUser`; también se genera un alias por cada nombre real.

`home/default.nix` es independiente de la identidad y selecciona el perfil
declarado. La misma configuración se integra en `#wsl` mediante
`modules/home/default.nix`; WSL desactiva las aplicaciones gráficas de
`developerTools`, Niri y Noctalia.

## NixOS-WSL

`nixosConfigurations.wsl` importa el módulo oficial de NixOS-WSL, las
features reutilizables y `modules/hosts/wsl`. Este host administra su usuario,
locales, shell e integración con Windows y Docker Desktop. Tanto el usuario
como el hostname y la zona horaria se resuelven desde el inventario efectivo.

## NixOS físico existente

`nixosConfigurations.existing` es un overlay de instalación, no un host con
hardware propio. Durante `apply-nixos-system.sh`, toma la ruta de la
configuración NixOS activa mediante `NIXOS_EXISTING_CONFIGURATION` y agrega el
perfil Niri. En evaluaciones puras usa un contenedor sintético para que la flake
siga siendo comprobable y portable.

El target completo de `install.sh` construye este sistema y Home Manager antes
de activar cualquiera de los dos. El repo no copia ni genera el hardware config
del equipo.

## Backends

`install.sh` centraliza Home Manager para NixOS existentes, conserva el
selector extensible y delega instalaciones de sistema a backends. El backend
incluido `holodeck-system-nixos` sólo implementa `--target wsl`; otros
sistemas pueden aportar un ejecutable o una app con el nombre
`holodeck-system-<backend>`.

## Límite de la instalación física

Se eliminaron:

- `modules/hosts/desktop`;
- el layout Disko;
- el instalador directo del desktop;
- el reinstalador kexec;
- toda selección, montaje, particionado y formateo de discos.

`verify-no-desktop.sh` impide que esas rutas y patrones destructivos vuelvan a
entrar. El overlay `#existing` sólo compone la configuración activa con módulos
reutilizables y no declara el layout de ningún host.

`nixosModules.niri-desktop` expone una composición reutilizable para un NixOS
existente. Habilita la sesión gráfica, pero deliberadamente no incorpora un
host físico, hardware config ni almacenamiento.

## Control declarativo del escritorio

El plugin de Noctalia es una vista Luau del estado deseado. Sólo invoca comandos
cerrados de `holodeckctl`; el backend normaliza el IR JSON, escribe de forma
atómica y delega la aplicación en `install.sh`. La flake vuelve a validar el
mismo schema antes de generar la configuración de Noctalia.

```text
Noctalia/Luau → holodeckctl → holodeck.local.json → Nix → build/switch
                ├──────────→ holodeck → GitHub / GitLab
                ├──────────→ aws → SSO / STS
                └──────────→ windowsvm → Docker / RDP / web
```

El resultado queda determinado por el source del repo, `flake.lock`, el IR
local y, para `#existing`, la configuración/hardware activos del equipo.
Las tres ramas de integración no se convierten en Nix: conservan autenticación
y estado runtime fuera del repo, y sólo reciben acciones allowlisted en una
terminal visible.

## Extender

Las preferencias de usuario viven bajo `modules/home/features`. Las features
de sistema viven bajo `modules/nixos/features` y quedan deshabilitadas por
default. Las relaciones concretas viven en las capas del inventario. Un nuevo backend
debe respetar:

```text
holodeck-system-BACKEND install --repo RUTA [argumentos]
```
