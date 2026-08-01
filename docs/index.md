# Documentación

El repositorio combina Home Manager standalone con un único host de sistema:
NixOS-WSL. No administra un desktop físico ni discos.

## Lectura recomendada

1. [Arquitectura](architecture.md): outputs, imports y límites.
2. [Home Manager](home-manager.md): perfil personal y aplicación.
3. [NixOS-WSL](wsl.md): host e instalación conservados.
4. [Holodeck](holodeck.md): core portable y backends.
5. [Mantenimiento](maintenance.md): checks y actualizaciones.
6. [Seguridad y secretos](security.md): estado que queda fuera de Git.

## Módulos reutilizables

- [Browser](browser.md)
- [Desktop feature](desktop-feature.md)
- [Features](features.md)
- [Git](git.md)
- [Python](python.md)
- [Node.js](nodejs.md)
- [Lean](lean.md)
- [Gráficos y GPU](graphics.md)
- [VSCodium](vscodium.md)
- [Contenedores y Windows VM](containers.md)

Estos módulos se conservan como biblioteca, aunque el repo ya no publique un
host de desktop físico que los active.
