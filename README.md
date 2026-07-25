# NixOS config

Configuracion personal de NixOS basada en flakes. El repo define los hosts
`desktop` y `wsl` en `x86_64-linux`, usa `nixpkgs` desde la rama `nixos-26.05`
y separa la configuracion en modulos reutilizables bajo `modules/`.

## Mapa rapido

```text
flake.nix
install-desktop.sh
install-wsl.sh
home/
  avivaldelli/
    default.nix
modules/
  parts.nix
  home/
    default.nix
    features/
      shell/
        default.nix
        completions.nix
      starship/
      aws/
    profiles/
      developer/
      minimal/
  hosts/
    desktop/
      default.nix
      disko.nix
      hardware-configuration.nix
    wsl/
      default.nix
  nixos/
    features/
      default.nix
      browser/
      desktop/
      git/
      python/
      nodejs/
      lean/
      graphics/
      vscodium/
      holodeck/
      containers/
        windowsvm/
docs/
```

## Uso diario

Aplicar la configuracion del desktop fisico:

```bash
sudo nixos-rebuild switch --flake .#desktop
```

Aplicar actualizaciones normales dentro de NixOS-WSL:

```bash
sudo nixos-rebuild switch --flake .#wsl
```

La primera instalacion de WSL cambia el usuario predeterminado y usa el wrapper:

```bash
./install-wsl.sh
```

`bootstrap-wsl.sh` sigue disponible como alias compatible.

Construir sin activar, eligiendo el host:

```bash
sudo nixos-rebuild build --flake .#desktop
sudo nixos-rebuild build --flake .#wsl
```

Actualizar el lockfile:

```bash
nix flake update
```

Validar la flake:

```bash
nix flake check
```

La misma validacion corre en GitHub Actions para pushes a `main` y pull
requests.

## Instalacion reproducible del desktop

El layout del disco fisico se declara con Disko en
`modules/hosts/desktop/disko.nix`:

- tabla GPT
- particion EFI de 1 GiB montada en `/boot`
- resto del disco cifrado con LUKS
- raiz ext4 en `/dev/mapper/cryptroot`
- sin UUID de una instalacion anterior

Desde un instalador NixOS iniciado en modo UEFI, clona el repo y localiza el
disco por su identificador estable:

```bash
lsblk
ls -l /dev/disk/by-id/
```

Despues ejecuta:

```bash
./install-desktop.sh /dev/disk/by-id/ID_DEL_DISCO
```

> [!CAUTION]
> El script borra por completo el disco indicado. Exige una ruta
> `/dev/disk/by-id/*`, muestra el modelo y numero de serie, y pide escribir una
> confirmacion exacta antes de ejecutar Disko.

El script crea y monta el layout, instala `#desktop` con `nixos-install` y pide
las contrasenas LUKS, root y `avivaldelli`. No se debe ejecutar
`nixos-rebuild` ni `switch-to-configuration` desde el sistema live.

## Instalacion unificada con Holodeck

Los dos entrypoints de instalacion son wrappers pequenos:

```bash
./install-desktop.sh /dev/disk/by-id/ID_DEL_DISCO
./install-wsl.sh
```

Ambos ejecutan la misma aplicacion de la flake y solamente fijan el host:

```text
install-desktop.sh -> holodeck system install --host desktop
install-wsl.sh     -> holodeck system install --host wsl
```

Tambien se puede invocar el orquestador directamente:

```bash
nix run .#holodeck -- system install \
  --host desktop \
  --disk /dev/disk/by-id/ID_DEL_DISCO

nix run .#holodeck -- system install --host wsl
```

Holodeck valida el repo y la flake antes de delegar en Disko,
`nixos-install` o `nixos-rebuild`. Nunca ejecuta el onboarding personal durante
la instalacion privilegiada. Despues de reiniciar e iniciar sesion como
`avivaldelli`, se completa sin `sudo`:

```bash
holodeck setup
```

Formatear archivos Nix:

```bash
nix fmt
```

Instalar el hook local contra secretos:

```bash
git config core.hooksPath .githooks
```

## Que configura hoy

- NixOS `desktop` con systemd-boot, GDM, GNOME, NetworkManager, PipeWire,
  Chromium, `wget`, `curl`, usuario `avivaldelli` y layout de disco declarativo
  mediante Disko.
- NixOS `wsl` con el mismo entorno terminal/developer y Home Manager, sin
  hardware configuration, bootloader fisico, desktop Linux, audio, impresion,
  drivers ni la VM Windows anidada; incluye Docker Desktop y `nix-ld` para
  VS Code Remote WSL.
- Locale base `en_US.UTF-8` con settings regionales `es_AR.UTF-8`.
- Zona horaria `America/Argentina/Buenos_Aires`.
- Feature `browser`: instala Chromium con configuracion minimalista preparada
  para personalizaciones futuras.
- Feature `desktop`: habilita el entorno de escritorio elegido; hoy GNOME con
  GDM y layout de teclado.
- Feature `git`: instala Git, Git LFS, delta y lazygit.
- Feature `python`: instala Python y `uv`.
- Feature `nodejs`: instala Node.js con npm y npx.
- Feature `lean`: instala `elan` para proyectos Lean y Lake.
- Feature `graphics`: habilita aceleracion grafica e instala `gpu-doctor` para
  recomendar drivers segun la GPU local.
- Feature `vscodium`: instala VSCodium y extensiones pinneadas.
- Feature `holodeck`: instala herramientas de desarrollo y un comando Python
  con colores para configurar perfiles Git, SSH, GPG, GitHub y GitLab.
- Feature `containers`: habilita Docker o Podman. En el host actual usa Docker.
- Feature `windowsVm`: agrega el comando `windowsvm` para correr una VM Windows
  via `dockurr/windows` dentro de Docker.
- Home Manager para `avivaldelli`: configura zsh, aliases, fzf, zoxide,
  direnv, starship y helpers AWS.

## Documentacion

- [Indice de docs](docs/index.md)
- [Arquitectura del repo](docs/architecture.md)
- [Host desktop](docs/desktop.md)
- [Host WSL](docs/wsl.md)
- [Home Manager](docs/home-manager.md)
- [Features](docs/features.md)
- [Browser](docs/browser.md)
- [Desktop feature](docs/desktop-feature.md)
- [Git](docs/git.md)
- [Python](docs/python.md)
- [Node.js](docs/nodejs.md)
- [Lean](docs/lean.md)
- [Graficos y GPU](docs/graphics.md)
- [VSCodium](docs/vscodium.md)
- [Holodeck](docs/holodeck.md)
- [Contenedores y Windows VM](docs/containers.md)
- [Mantenimiento](docs/maintenance.md)
- [Seguridad y secretos](docs/security.md)

## Principios del repo

- La flake declara sistemas reproducibles; el estado local vive fuera del repo.
- Los modulos de features exponen opciones bajo `features.*`.
- El host decide que features activar.
- Home Manager declara preferencias y dotfiles del usuario.
- Imagenes, extensiones y entradas externas se pinnean con version, digest o hash.
- Secretos, llaves privadas y tokens no se versionan.
