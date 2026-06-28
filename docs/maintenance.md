# Mantenimiento

Comandos y flujos comunes para operar el repo.

## Construir y aplicar

Construir sin activar:

```bash
sudo nixos-rebuild build --flake .#desktop
```

Aplicar ahora:

```bash
sudo nixos-rebuild switch --flake .#desktop
```

Probar hasta el proximo reboot:

```bash
sudo nixos-rebuild test --flake .#desktop
```

Crear una generacion para el proximo boot:

```bash
sudo nixos-rebuild boot --flake .#desktop
```

## Validar

```bash
nix flake check
```

Tambien es util revisar espacios o conflictos de patch:

```bash
git diff --check
```

## Actualizar nixpkgs

Actualizar todos los inputs:

```bash
nix flake update
```

Actualizar solo `nixpkgs`:

```bash
nix flake lock --update-input nixpkgs
```

Despues:

```bash
sudo nixos-rebuild build --flake .#desktop
sudo nixos-rebuild switch --flake .#desktop
```

## Revisar cambios

```bash
git status --short
git diff
```

Ver generaciones:

```bash
sudo nix-env --list-generations --profile /nix/var/nix/profiles/system
```

Volver a la generacion anterior desde bootloader sigue disponible mientras no se
eliminen generaciones viejas.

## Hooks

El repo trae `.githooks/pre-commit` para bloquear secretos obvios en archivos
stageados. Activarlo una vez:

```bash
git config core.hooksPath .githooks
```

El hook revisa:

- paths como `.env`, `.ssh`, `.gnupg`, `secrets`, `private`
- llaves privadas
- extensiones sensibles como `.pem`, `.key`, `.p12`, `.gpg`, `.age`, `.kdbx`
- patrones comunes de tokens de GitHub, GitLab, AWS y Slack

## Cuando cambia hardware

Si esta configuracion se mueve a otra maquina:

1. Generar hardware config con `nixos-generate-config`.
2. Comparar contra `modules/hosts/desktop/hardware-configuration.nix`.
3. Reemplazar solo despues de revisar discos, LUKS, boot y CPU.
4. Construir antes de hacer switch.

## Cuando falla una imagen o extension

Si Nix falla por hash incorrecto:

1. Confirmar que la version o digest sea la que queres.
2. Leer el hash esperado que muestra Nix.
3. Reemplazar el hash en `images.json` o `extensions.json`.
4. Volver a construir.

## Limpieza

Recolectar generaciones viejas:

```bash
sudo nix-collect-garbage --delete-older-than 14d
```

Optimizar store:

```bash
nix store optimise
```

No borrar manualmente contenido de `/nix/store`.

