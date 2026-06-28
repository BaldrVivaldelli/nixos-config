# Features

Las features de NixOS son modulos reutilizables bajo `modules/nixos/features`.
Todas se importan automaticamente, pero solo aplican cambios cuando su opcion
`enable` esta activa.

## Resumen

| Feature | Opcion | Que hace |
| --- | --- | --- |
| Python | `features.python` | Instala Python y uv para desarrollo. |
| Node.js | `features.nodejs` | Instala Node.js con npm y npx para desarrollo. |
| Graphics | `features.graphics` | Habilita aceleracion grafica y agrega `gpu-doctor`. |
| VSCodium | `features.vscodium` | Instala VSCodium y extensiones pinneadas. |
| Holodeck | `features.holodeck` | Instala CLI de Git/GitHub/GitLab/GPG/SSH y el comando Python `holodeck`. |
| Containers | `features.containers` | Habilita Docker o Podman y opcionalmente carga imagenes declarativas. |
| Windows VM | `features.containers.windowsVm` | Agrega `windowsvm` para correr Dockurr Windows en Docker. |

## Activacion

Las features se activan desde un host:

```nix
features.python.enable = true;
features.nodejs.enable = true;
features.graphics.enable = true;
features.vscodium.enable = true;
features.holodeck.enable = true;
features.containers.enable = true;
```

## Donde documentar cambios

- Cambios generales de una feature: actualizar este archivo.
- Detalles de Python: [python.md](python.md).
- Detalles de Node.js: [nodejs.md](nodejs.md).
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
