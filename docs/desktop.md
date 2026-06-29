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

El host usa systemd-boot:

```nix
boot.loader.systemd-boot.enable = true;
boot.loader.efi.canTouchEfiVariables = true;
```

`hardware-configuration.nix` fue generado por `nixos-generate-config` y describe:

- root en `ext4` sobre LUKS
- `/boot` en `vfat`
- CPU AMD con microcode redistribuible cuando corresponde
- modulo `kvm-amd`
- sin swap configurada

Ese archivo es especifico de la maquina. Al migrar a otra computadora, generar
uno nuevo y revisarlo antes de hacer switch.

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
