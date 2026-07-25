# Documentacion

Este directorio explica como esta armado el repo, como operarlo y donde tocar
cuando quieras agregar o cambiar algo.

## Lectura recomendada

1. [Arquitectura](architecture.md): import graph, convenciones y como agregar
   hosts o features.
2. [Host desktop](desktop.md): configuracion concreta de la maquina fisica.
3. [Host WSL](wsl.md): entorno de desarrollo sobre NixOS-WSL.
4. [Home Manager](home-manager.md): configuracion declarativa del usuario.
5. [Features](features.md): resumen de los modulos activables.
6. [Mantenimiento](maintenance.md): comandos habituales, updates y checks.
7. [Seguridad y secretos](security.md): que no debe entrar al repo.

## Guias por feature

- [Browser](browser.md)
- [Desktop feature](desktop-feature.md)
- [Git](git.md)
- [Python](python.md)
- [Node.js](nodejs.md)
- [Lean](lean.md)
- [Graficos y GPU](graphics.md)
- [VSCodium](vscodium.md)
- [Holodeck](holodeck.md)
- [Contenedores y Windows VM](containers.md)

## Estado local fuera del repo

Algunas features generan estado en el sistema:

- Holodeck usa `~/.config/holodeck`, `~/.ssh`, `~/.gitconfig`, `~/.ssh/config`
  y el keyring de GPG.
- Docker mantiene imagenes, contenedores y volumenes en el estado local del
  daemon.
- `windowsvm` usa por defecto `~/containers/windows/storage` y
  `~/containers/windows/shared`.

Ese estado no debe versionarse.
