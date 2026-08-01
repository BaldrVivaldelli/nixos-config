# Arquitectura

La flake expone Home Manager standalone, NixOS-WSL y dos comandos Holodeck.

```text
flake.nix
├── homeConfigurations.avivaldelli
│   └── home/avivaldelli
│       └── modules/home/profiles/developer
├── nixosConfigurations.wsl
│   ├── nixos-wsl.nixosModules.default
│   ├── modules/parts.nix
│   │   ├── modules/home
│   │   └── modules/nixos/features
│   └── modules/hosts/wsl
├── apps.holodeck
│   └── packages/holodeck
│       └── holodeck/core
└── apps.holodeck-system-nixos
    └── holodeck/backends/nixos
```

## Home Manager

`homeConfigurations.avivaldelli` permite construir y activar únicamente el
perfil del usuario. La configuración base también se integra en `#wsl`
mediante `modules/home/default.nix`; WSL desactiva las aplicaciones gráficas
de `developerTools`.

## NixOS-WSL

`nixosConfigurations.wsl` importa el módulo oficial de NixOS-WSL, las
features reutilizables y `modules/hosts/wsl`. Este host administra su usuario,
locales, shell e integración con Windows y Docker Desktop.

## Backends

`install.sh` centraliza Home Manager para NixOS existentes, conserva el
selector extensible y delega instalaciones de sistema a backends. El backend
incluido `holodeck-system-nixos` sólo implementa `--target wsl`; otros
sistemas pueden aportar un ejecutable o una app con el nombre
`holodeck-system-<backend>`.

## Límite del desktop físico

Se eliminaron:

- `modules/hosts/desktop`;
- el layout Disko;
- el instalador directo del desktop;
- el reinstalador kexec;
- toda selección, montaje, particionado y formateo de discos.

`verify-no-desktop.sh` impide que esas rutas y patrones vuelvan a entrar. Los
módulos de features permanecen porque son reutilizables y no declaran el layout
de ningún host.

## Extender

Las preferencias de usuario viven bajo `modules/home/features`. Las features
de sistema viven bajo `modules/nixos/features` y quedan deshabilitadas por
default. Un nuevo backend debe respetar:

```text
holodeck-system-BACKEND install --repo RUTA [argumentos]
```
