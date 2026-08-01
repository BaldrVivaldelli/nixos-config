# Home Manager y NixOS-WSL

Este repositorio mantiene dos flujos:

- una configuración standalone de Home Manager para `avivaldelli`;
- el host `#wsl` y su instalador para NixOS-WSL.

La instalación del desktop físico fue retirada. El repo no contiene layouts de
disco, Disko, UUID, LUKS ni un reinstalador que pueda particionar o formatear
unidades.

## Home Manager sobre un NixOS existente

Ejecutar como usuario normal, sin `sudo`:

```bash
./install.sh home-manager
```

Ese target centraliza, en orden:

1. `./verify-user-only.sh`;
2. `./apply-home.sh build`;
3. `./apply-home.sh switch`.

Si falla la validación o el build, no ejecuta el switch. Después de la primera
activación quedan disponibles `hmbuild`, `hmswitch` y `hmverify`.

El perfil instala Zsh, Starship, Git, Python, Node.js, AWS CLI, Chromium,
VSCodium y Holodeck, entre otras herramientas de usuario.

## NixOS-WSL

Desde una sesión NixOS-WSL:

```bash
./install.sh nixos wsl
```

También se puede ejecutar el backend directamente:

```bash
nix --extra-experimental-features "nix-command flakes" \
  run .#holodeck-system-nixos -- install --target wsl
```

El selector genérico `install.sh` conserva el contrato
`holodeck-system-<backend>` para integraciones externas. El backend NixOS de
este repo acepta solamente `wsl`; no tiene parámetros ni código de discos.

Las actualizaciones del sistema WSL se aplican con:

```bash
sudo nixos-rebuild switch --flake .#wsl
```

## Estructura

```text
flake.nix
install.sh
home/avivaldelli/
modules/
  home/
  hosts/wsl/
  nixos/features/
holodeck/
  core/
  backends/nixos/
packages/holodeck/
```

Los módulos NixOS bajo `modules/nixos/features` se conservan como piezas
reutilizables. El único host NixOS publicado actualmente es `#wsl`.

## Validación

```bash
./verify-user-only.sh
./verify-no-desktop.sh
nix --extra-experimental-features "nix-command flakes" \
  flake check --print-build-logs
```

CI ejecuta los mismos límites antes de evaluar la flake.

## Documentación

- [Índice](docs/index.md)
- [Arquitectura](docs/architecture.md)
- [Home Manager](docs/home-manager.md)
- [NixOS-WSL](docs/wsl.md)
- [Holodeck](docs/holodeck.md)
- [Mantenimiento](docs/maintenance.md)
- [Seguridad y secretos](docs/security.md)
