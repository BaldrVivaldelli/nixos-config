# Host desktop

`modules/hosts/desktop` contiene la configuracion concreta de la maquina
`desktop`.

## Datos principales

- Hostname: `nixos`
- Plataforma: `x86_64-linux`
- Timezone: `America/Argentina/Buenos_Aires`
- Locale base: `en_US.UTF-8`
- Settings regionales: `es_AR.UTF-8`
- Display manager: GDM
- Desktop environment: GNOME
- Red: NetworkManager
- Audio: PipeWire con ALSA y PulseAudio compatibility
- Browser: Chromium
- Usuario normal: `avivaldelli`
- Grupos del usuario: `networkmanager`, `wheel`
- Shell del usuario: zsh
- Home Manager integrado para `avivaldelli`
- Nix experimental features: `nix-command`, `flakes`
- `nixpkgs.config.allowUnfree = true`
- `system.stateVersion = "26.05"`

## Boot y hardware

El host usa systemd-boot y fija explicitamente la ESP en `/boot`:

```nix
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;
boot.loader.efi.efiSysMountPoint = "/boot";
```

Disko declara el layout en `modules/hosts/desktop/disko.nix`:

- una tabla GPT sobre un unico disco
- una ESP de 1 GiB, `vfat`, montada en `/boot`
- el resto del disco como LUKS interactivo llamado `cryptroot`
- root `ext4` sobre `/dev/mapper/cryptroot`

Disko genera `fileSystems` y `boot.initrd.luks.devices` a partir de nombres de
particion estables. Por eso `hardware-configuration.nix` ya no contiene UUID de
root ni de EFI; conserva solamente los modulos de kernel y datos de CPU
detectados para esta maquina.

## Instalacion desde cero

> [!CAUTION]
> Este procedimiento destruye todas las particiones y datos del disco elegido.
> No soporta dual boot.

Arranca el instalador NixOS en modo UEFI, clona el repositorio y ejecuta:

```bash
./install-desktop.sh
```

El entrypoint delega directamente en el backend NixOS:

```bash
nix run .#holodeck-system-nixos -- install --target desktop
```

Antes de borrar nada, `holodeck-system-nixos`:

1. exige que el live ISO este iniciado en UEFI
2. busca discos completos con un ID estable en `/dev/disk/by-id`
3. excluye cualquier disco que sostenga `/`, el Nix store o el medio live
4. prefiere discos internos frente a dispositivos removibles
5. elige automaticamente si queda uno, o muestra un selector si quedan varios
6. muestra nombre, capacidad, modelo, numero de serie y usos activos
7. exige escribir `BORRAR` seguido por el ID seleccionado
8. desactiva automaticamente su swap y desmonta todas sus particiones
9. revalida que el disco quedo libre antes de ejecutar Disko

El override `--disk /dev/disk/by-id/ID` sigue disponible para recuperacion o
hardware ambiguo, pero no hace falta en el flujo normal.

Despues Disko crea, formatea y monta todo en `/mnt`. La instalacion se completa
con `nixos-install --flake .#desktop`, no con `nixos-rebuild`. Durante el flujo
se solicitan la frase LUKS y las contrasenas de root y `avivaldelli`. Al
terminar, el backend sincroniza y desmonta `/mnt` automaticamente.

La ruta de dispositivo por defecto que aparece en `disko.nix` es un marcador
invalido a proposito. El script pasa el disco real con `--argstr device`, por lo
que no queda ningun UUID ni nombre `/dev/nvme*` ligado a una instalacion
anterior.

Despues del reinicio, el onboarding de identidad y credenciales se ejecuta como
usuario normal:

```bash
holodeck setup
```

El instalador no llama ese comando como `root`.

## Features activadas

El host activa:

```nix
features.browser.enable = true;
features.desktop.enable = true;
features.git.enable = true;
features.python.enable = true;
features.nodejs.enable = true;
features.lean.enable = true;
# >>> gpu-doctor graphics
features.graphics = {
  enable = true;
  driver = "amd";
  enable32Bit = false;
};
# <<< gpu-doctor graphics
features.vscodium.enable = true;
features.holodeck.enable = true;
features.containers = {
  enable = true;
  engine = "docker";
  users = [ "avivaldelli" ];
  windowsVm.enable = true;
};
```

Esto instala Chromium, GNOME/GDM, Git tooling, Python, uv, Node.js, Lean,
aceleracion grafica base, `gpu-doctor`, VSCodium, Holodeck, Docker y el helper
`windowsvm`. La configuracion interactiva del usuario se define en
`home/avivaldelli`.

## Home Manager

`modules/parts.nix` integra Home Manager como modulo NixOS:

```nix
inputs.home-manager.nixosModules.home-manager
```

El usuario configurado es `avivaldelli`, con archivos en:

```text
home/avivaldelli/
```

Como Home Manager esta integrado al sistema, los cambios se aplican con el mismo
comando:

```bash
sudo nixos-rebuild switch --flake .#desktop
```

## Cambios comunes

Cambiar hostname:

```nix
networking.hostName = "nuevo-nombre";
```

Cambiar layout de teclado:

```nix
features.desktop.keyboard = {
  layout = "latam";
  variant = "";
};
```

Agregar paquetes del sistema:

```nix
environment.systemPackages = with pkgs; [
  wget
  curl
  tree
];
```

Agregar paquetes solo al usuario:

```nix
users.users."avivaldelli".packages = with pkgs; [
  thunderbird
];
```

## Aplicar cambios

```bash
sudo nixos-rebuild switch --flake .#desktop
```

Para probar hasta el proximo reboot:

```bash
sudo nixos-rebuild test --flake .#desktop
```

Para crear una generacion bootable sin activarla ahora:

```bash
sudo nixos-rebuild boot --flake .#desktop
```
