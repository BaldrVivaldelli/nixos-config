# NixOS config

Configuracion personal de NixOS basada en flakes. El repo define los hosts
`desktop` y `wsl` en `x86_64-linux`, usa `nixpkgs` desde la rama `nixos-26.05`
y separa la configuracion en modulos reutilizables bajo `modules/`.

## Mapa rapido

```text
flake.nix
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

La primera instalacion de WSL cambia el usuario predeterminado y debe hacerse
con el procedimiento de [`FIRST_RUN_WSL.md`](FIRST_RUN_WSL.md), usando:

```bash
./bootstrap-wsl.sh
```

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
  Chromium, `wget`, `curl` y usuario `avivaldelli`.
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
- [Primera instalacion WSL](FIRST_RUN_WSL.md)
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
