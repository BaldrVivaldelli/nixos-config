# Mantenimiento

## NixOS físico existente

```bash
./install.sh existing-nixos
```

Este comando verifica y construye primero NixOS y Home Manager, y luego activa
ambos. Para validar sólo el sistema sin activarlo:

```bash
./apply-nixos-system.sh build
```

El build reutiliza `/etc/nixos/configuration.nix` y no escribe dentro de
`/etc/nixos`.

## Home Manager standalone

```bash
./install.sh home-manager
```

Este comando aplica solamente el perfil de usuario. Se ejecuta como usuario
normal. Para validar sin activar todavía se puede usar
`./apply-home.sh build`.

## NixOS-WSL

```bash
sudo nixos-rebuild build --flake path:.#wsl
sudo nixos-rebuild switch --flake path:.#wsl
```

La primera preparación puede hacerse con `./install.sh nixos wsl`.

## Checks

```bash
./verify-user-only.sh
./verify-no-desktop.sh
nix --extra-experimental-features "nix-command flakes" \
  flake check path:. --print-build-logs
```

El primer script comprueba el límite de la configuración Home Manager. El
segundo rechaza instaladores destructivos, Disko y patrones de almacenamiento.
El check de la flake evalúa además `#existing`, `#wsl` y ejecuta las pruebas de
Holodeck e instaladores.

## Formato

```bash
nix --extra-experimental-features "nix-command flakes" fmt
```

## Actualizar inputs

```bash
nix --extra-experimental-features "nix-command flakes" flake update
nix --extra-experimental-features "nix-command flakes" flake check path:.
```

Revisar siempre `flake.lock` antes de activar el perfil o el sistema WSL.
