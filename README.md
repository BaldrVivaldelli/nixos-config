# NixOS existente, Home Manager y NixOS-WSL

Este repositorio mantiene tres flujos:

- un overlay seguro para configurar Niri sobre un NixOS físico existente;
- una configuración standalone de Home Manager seleccionada por inventario;
- el host `#wsl` y su instalador para NixOS-WSL.

La reinstalación desde cero del desktop físico fue retirada. El flujo existente
parte de la configuración activa del equipo y no contiene layouts de disco,
Disko, UUID, LUKS ni código que pueda particionar o formatear unidades.

## Primera ejecución

No hace falta preparar el inventario manualmente. La primera vez basta con
abrir el instalador:

```bash
./install.sh
```

Después de elegir NixOS físico, Home Manager o NixOS-WSL, el instalador nota
que todavía no existe `inventory.local.nix`, consulta al sistema y autocompleta:

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

## NixOS físico existente: instalación completa

Ejecutar como usuario normal, sin `sudo`:

```bash
./install.sh
# elegir 1) NixOS físico existente: Niri + Home Manager
```

También se puede seleccionar directamente:

```bash
./install.sh existing-nixos
```

Ese target reutiliza `/etc/nixos/configuration.nix` y su
`hardware-configuration.nix`, y superpone el perfil Niri del repositorio sin
copiar esas configuraciones al repo. Ejecuta, en orden:

1. verificaciones de seguridad;
2. build del sistema NixOS con Niri;
3. build de Home Manager;
4. switch del sistema, que registra Niri y lo deja predeterminado en SDDM;
5. switch de Home Manager.

Si alguna verificación o build falla, no comienza los switches. El instalador
pide `sudo` únicamente para los dos pasos de NixOS; debe iniciarse como usuario
normal. No edita `/etc/nixos` ni incorpora hardware, discos, UUID, filesystems,
particiones o bootloader al repositorio.

Para aplicar solamente la configuración de usuario, sin reconstruir NixOS:

```bash
./install.sh home-manager
```

Después de la primera activación quedan disponibles `hmbuild`, `hmswitch` y
`hmverify`.

El perfil instala Zsh, Starship, Git, Python, Node.js, AWS CLI, Chromium,
VSCodium, Niri, Noctalia y Holodeck, entre otras herramientas de usuario. Niri
inicia Noctalia automáticamente dentro de su sesión.

Al terminar, alcanza con cerrar la sesión de KDE y entrar a Niri desde SDDM; no
es necesario reiniciar. Plasma permanece disponible como alternativa. Ver
[docs/niri.md](docs/niri.md).

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
apply-nixos-system.sh
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
