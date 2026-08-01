# Mantenimiento

## Home Manager standalone

```bash
./install.sh home-manager
```

Este comando verifica, construye y activa el perfil. Se ejecuta como usuario
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
segundo rechaza hosts físicos, Disko y patrones de almacenamiento. El check de
la flake evalúa además `#wsl` y ejecuta las pruebas de Holodeck e instaladores.

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
