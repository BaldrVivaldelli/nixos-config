# NixOS config

Configuracion personal de NixOS basada en flakes. El repo define una maquina
`desktop` en `x86_64-linux`, usa `nixpkgs` desde la rama `nixos-26.05` y separa
la configuracion en modulos reutilizables bajo `modules/`.

## Mapa rapido

```text
flake.nix
modules/
  parts.nix
  hosts/
    desktop/
      default.nix
      hardware-configuration.nix
  features/
    default.nix
    python/
    vscodium/
    holodeck/
    containers/
      windowsvm/
docs/
```

## Uso diario

Aplicar la configuracion del host actual:

```bash
sudo nixos-rebuild switch --flake .#desktop
```

Construir sin activar:

```bash
sudo nixos-rebuild build --flake .#desktop
```

Actualizar el lockfile:

```bash
nix flake update
```

Validar la flake:

```bash
nix flake check
```

Instalar el hook local contra secretos:

```bash
git config core.hooksPath .githooks
```

## Que configura hoy

- NixOS `desktop` con systemd-boot, GDM, GNOME, NetworkManager, PipeWire,
  Firefox, `wget`, `curl` y usuario `avivaldelli`.
- Locale base `en_US.UTF-8` con settings regionales `es_AR.UTF-8`.
- Zona horaria `America/Argentina/Buenos_Aires`.
- Feature `python`: instala Python y `uv`.
- Feature `vscodium`: instala VSCodium y extensiones pinneadas.
- Feature `holodeck`: instala herramientas de desarrollo y un comando Python
  con colores para configurar perfiles Git, SSH, GPG, GitHub y GitLab.
- Feature `containers`: habilita Docker o Podman. En el host actual usa Docker.
- Feature `windowsVm`: agrega el comando `windowsvm` para correr una VM Windows
  via `dockurr/windows` dentro de Docker.

## Documentacion

- [Indice de docs](docs/index.md)
- [Arquitectura del repo](docs/architecture.md)
- [Host desktop](docs/desktop.md)
- [Features](docs/features.md)
- [Python](docs/python.md)
- [VSCodium](docs/vscodium.md)
- [Holodeck](docs/holodeck.md)
- [Contenedores y Windows VM](docs/containers.md)
- [Mantenimiento](docs/maintenance.md)
- [Seguridad y secretos](docs/security.md)

## Principios del repo

- La flake declara sistemas reproducibles; el estado local vive fuera del repo.
- Los modulos de features exponen opciones bajo `features.*`.
- El host decide que features activar.
- Imagenes, extensiones y entradas externas se pinnean con version, digest o hash.
- Secretos, llaves privadas y tokens no se versionan.
