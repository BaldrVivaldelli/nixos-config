# Home Manager y NixOS-WSL

Este repositorio mantiene dos flujos:

- una configuración standalone de Home Manager seleccionada por inventario;
- el host `#wsl` y su instalador para NixOS-WSL.

La instalación del desktop físico fue retirada. El repo no contiene layouts de
disco, Disko, UUID, LUKS ni un reinstalador que pueda particionar o formatear
unidades.

## Primera ejecución

No hace falta preparar el inventario manualmente. La primera vez basta con
abrir el instalador:

```bash
./install.sh
```

Después de elegir Home Manager o NixOS-WSL, el instalador nota que todavía no
existe `inventory.local.nix`, consulta al sistema y autocompleta:

- usuario y home;
- ruta absoluta y relativa del repositorio;
- hostname;
- arquitectura y plataforma Nix;
- zona horaria;
- si la sesión corre dentro de WSL.

Antes de guardar muestra todos los valores y pide confirmación. Si se cancela,
no crea el archivo ni continúa con la instalación. En ejecuciones posteriores
reutiliza ese inventario y no vuelve a preguntar.

El archivo es específico de la máquina y Git lo ignora. El proceso no consulta
ni modifica discos, particiones, UUID o montajes.

La detección también se puede ejecutar o revisar por separado:

```bash
./install.sh configure          # detecta, confirma y guarda
./install.sh configure --print  # sólo muestra la propuesta
```

En CI o una ejecución sin terminal se mantienen los defaults versionados sin
preguntar ni bloquear el proceso. Para generar el inventario deliberadamente
en ese contexto se puede usar `./install.sh configure --yes`.

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
VSCodium, Niri, Noctalia y Holodeck, entre otras herramientas de usuario. Niri
inicia Noctalia automáticamente dentro de su sesión.

Para registrar Niri y preseleccionarlo en SDDM, una instalación física
existente puede importar `modules/nixos/profiles/niri-desktop`; ese perfil no
contiene hardware ni almacenamiento. Ver [docs/niri.md](docs/niri.md).

`inventory.nix` contiene defaults portables y `inventory.local.nix` los datos
detectados de cada máquina. Los scripts usan `homeConfigurations.default`, por
lo que un cambio de usuario no requiere renombrar carpetas ni modificar
comandos. Ver [docs/inventory.md](docs/inventory.md).

## NixOS-WSL

Desde una sesión NixOS-WSL:

```bash
./install.sh nixos wsl
```

También se puede ejecutar el backend directamente:

```bash
nix --extra-experimental-features "nix-command flakes" \
  run path:.#holodeck-system-nixos -- install --target wsl
```

El selector genérico `install.sh` conserva el contrato
`holodeck-system-<backend>` para integraciones externas. El backend NixOS de
este repo acepta solamente `wsl`; no tiene parámetros ni código de discos.

Las actualizaciones del sistema WSL se aplican con:

```bash
sudo nixos-rebuild switch --flake path:.#wsl
```

## Estructura

```text
flake.nix
inventory.nix
inventory.local.nix  # generado localmente e ignorado por Git
configure-inventory.sh
install.sh
home/default.nix
lib/inventory.nix
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
  flake check path:. --print-build-logs
```

CI ejecuta los mismos límites antes de evaluar la flake.

## Documentación

- [Índice](docs/index.md)
- [Arquitectura](docs/architecture.md)
- [Inventario](docs/inventory.md)
- [Home Manager](docs/home-manager.md)
- [NixOS-WSL](docs/wsl.md)
- [Holodeck](docs/holodeck.md)
- [Mantenimiento](docs/maintenance.md)
- [Seguridad y secretos](docs/security.md)
