# Features

Las features de NixOS son modulos reutilizables bajo `modules/nixos/features`.
Todas se importan automaticamente, pero solo aplican cambios cuando su opcion
`enable` esta activa.

## Resumen

| Feature | Opcion | Que hace |
| --- | --- | --- |
| Browser | `features.browser` | Instala Chromium y deja lista su configuracion declarativa. |
| Desktop | `features.desktop` | Habilita el entorno de escritorio elegido; hoy GNOME con GDM. |
| Git | `features.git` | Instala Git, Git LFS, delta y lazygit. |
| Python | `features.python` | Instala Python y uv para desarrollo. |
| Node.js | `features.nodejs` | Instala Node.js con npm y npx para desarrollo. |
| Lean | `features.lean` | Instala elan para proyectos Lean y Lake. |
| Graphics | `features.graphics` | Habilita aceleracion grafica y agrega `gpu-doctor`. |
| VSCodium | `features.vscodium` | Instala VSCodium y extensiones pinneadas. |
| Holodeck | `features.holodeck` | Instala CLI de Git/GitHub/GitLab/GPG/SSH y el comando Python `holodeck`. |
| Containers | `features.containers` | Habilita Docker o Podman y opcionalmente carga imagenes declarativas. |
| Windows VM | `features.containers.windowsVm` | Agrega `windowsvm` para correr Dockurr Windows en Docker. |

## Activacion

Las features se activan desde un host:

```nix
features.browser.enable = true;
features.desktop.enable = true;
features.git.enable = true;
features.python.enable = true;
features.nodejs.enable = true;
features.lean.enable = true;
features.graphics.enable = true;
features.vscodium.enable = true;
features.holodeck.enable = true;
features.containers.enable = true;
```

## Donde documentar cambios

- Cambios generales de una feature: actualizar este archivo.
- Detalles de Browser: [browser.md](browser.md).
- Detalles de Desktop: [desktop-feature.md](desktop-feature.md).
- Detalles de Git: [git.md](git.md).
- Detalles de Python: [python.md](python.md).
- Detalles de Node.js: [nodejs.md](nodejs.md).
- Detalles de Lean: [lean.md](lean.md).
- Detalles de graficos y GPU: [graphics.md](graphics.md).
- Detalles de VSCodium: [vscodium.md](vscodium.md).
- Detalles de Holodeck: [holodeck.md](holodeck.md).
- Detalles de Docker, Podman o Windows VM: [containers.md](containers.md).

## Patron recomendado para nuevas features

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.features.myFeature;
in
{
  options.features.myFeature = {
    enable = lib.mkEnableOption "my feature";
  };

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.example ];
  };
}
```

Mantener el estado local fuera del repo y exponer opciones para lo que convenga
ajustar desde cada host.
