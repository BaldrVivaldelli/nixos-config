# Host WSL

El host `wsl` reutiliza la capa común del repositorio y el usuario lógico
asignado en `inventory.hosts.wsl`, pero delega a NixOS-WSL todo lo relacionado
con kernel, bootloader, montajes de Windows, networking e inicio del entorno.

## Import graph

```text
nixosConfigurations.wsl
  -> inputs.nixos-wsl.nixosModules.default
  -> modules/parts.nix
       -> Home Manager
       -> modules/home
       -> modules/nixos/features
  -> modules/hosts/wsl/default.nix
```

## Features habilitadas

- `features.git`
- `features.python`
- `features.nodejs`
- `features.lean`
- `features.holodeck`
- Home Manager `developer`: zsh, aliases, completions, fzf, zoxide, direnv,
  starship y helpers AWS.
- Integracion con Docker Desktop.
- `nix-ld` para conectar VS Code Remote WSL desde Windows.

## Componentes omitidos intencionalmente

- `hardware-configuration.nix`
- systemd-boot y configuracion EFI
- NetworkManager
- CUPS
- PipeWire y RTKit
- GNOME y GDM
- Chromium
- drivers graficos del host fisico
- VSCodium para Linux
- Docker nativo del modulo `features.containers`
- `dockurr/windows` y `features.containers.windowsVm`

NixOS-WSL sigue usando systemd para administrar el entorno de la distribucion.
Lo que se omite es `systemd-boot`, que es el bootloader de la maquina fisica.

## Primera activacion

Usa el script de la raiz:

```bash
./install.sh nixos wsl
```

El selector delega en:

```bash
nix run path:.#holodeck-system-nixos -- install --target wsl
```

El backend usa el NixOS-WSL fijado en `flake.lock`, valida la flake y ejecuta:

```bash
sudo nixos-rebuild boot --flake path:.#wsl
```

Despues hay que salir de WSL y completar el ciclo de reinicio desde PowerShell
que muestra el propio comando. La nueva sesión debe usar el username y hostname
declarados en el inventario efectivo; entonces se configura la identidad personal sin
`sudo`:

```bash
holodeck setup
```

## Actualizaciones posteriores

```bash
cd /ruta/detectada/al/nixos-config
sudo nixos-rebuild switch --flake path:.#wsl
```

## VS Code / Kiro desde Windows

El host habilita:

```nix
programs.nix-ld.enable = true;
```

Esto permite ejecutar el servidor remoto de VS Code, que descarga un binario
Node.js convencional. El editor sigue instalado y ejecutandose en Windows; el
workspace, terminal y herramientas viven dentro de NixOS-WSL.

## Lockfile y Git

El snapshot conserva las revisiones fijadas de `nixpkgs`, Home Manager y
NixOS-WSL. No hace falta regenerar el lock para la primera instalacion. Para
actualizar solamente NixOS-WSL mas adelante:

```bash
nix --extra-experimental-features "nix-command flakes" flake update nixos-wsl
git add flake.lock
git commit -m "Update NixOS-WSL input"
git push
```
