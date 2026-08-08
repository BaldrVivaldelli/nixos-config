# Mantenimiento

## NixOS físico existente

```bash
./install.sh existing-nixos
```

Este comando verifica y construye primero candidatos exactos de NixOS y Home
Manager, y luego activa esos mismos store paths. También instala Docker,
`windowsvm` y sus completions. Para validar sólo
el sistema sin activarlo:

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

Para regenerar Home Manager y recargar el plugin de Holodeck Control en una
sola operación:

```bash
holodeck-regenerate
# Equivalente desde el repositorio: ./install.sh regenerate
```

## NixOS-WSL

```bash
./install.sh nixos wsl
```

El backend valida y activa desde el mismo snapshot seguro.

## Recovery

Cada aplicación centralizada imprime la ruta de su manifiesto. Ante una
activación fallida —o si se necesita volver explícitamente a las generaciones
registradas— ejecutar:

```bash
./install.sh recover /ruta/al/manifest
```

El recovery valida que el manifiesto sea un archivo privado del usuario,
restaura primero Home Manager y luego NixOS, siempre por store path exacto.

## Checks

```bash
./verify-user-only.sh
./verify-no-desktop.sh
./prepare-flake-source.sh --check --print-build-logs
```

El primer script comprueba el límite de la configuración Home Manager. El
segundo rechaza instaladores destructivos, Disko y patrones de almacenamiento.
El check de la flake evalúa el fixture aislado `existingTest`, `#wsl` y ejecuta las pruebas de
Holodeck, instaladores, `holodeckctl` y el plugin Luau. El artefacto del
plugin se compila con Luau y se valida con el binario de Noctalia fijado.

El backend también se puede revisar sin aplicar cambios:

```bash
holodeckctl status
holodeckctl init  # sólo si todavía no existe holodeck.local.json
holodeckctl plan
```

## Formato

```bash
nix --extra-experimental-features "nix-command flakes" fmt
```

## Actualizar inputs

```bash
nix --extra-experimental-features "nix-command flakes" flake update
./prepare-flake-source.sh --check
```

Revisar siempre `flake.lock` antes de activar el perfil o el sistema WSL.
