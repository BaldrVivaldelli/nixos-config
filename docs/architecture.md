# Arquitectura

El repo usa flakes y modulos NixOS. La flake expone dos configuraciones:
`nixosConfigurations.desktop` y `nixosConfigurations.wsl`.

## Import graph

```text
flake.nix
  apps.holodeck
    ./modules/nixos/features/holodeck/package.nix
    ./modules/nixos/features/holodeck/app
  apps.disko
  nixosConfigurations.desktop
    inputs.disko.nixosModules.disko
    ./modules/parts.nix
      inputs.home-manager.nixosModules.home-manager
      ./modules/home/default.nix
        ./home/avivaldelli
          ./modules/home/profiles/developer
            ./modules/home/features/shell
              ./modules/home/features/shell/completions.nix
            ./modules/home/features/starship
            ./modules/home/features/aws
      ./modules/nixos/features/default.nix
        ./modules/nixos/features/browser
        ./modules/nixos/features/desktop
        ./modules/nixos/features/git
        ./modules/nixos/features/python
        ./modules/nixos/features/nodejs
        ./modules/nixos/features/lean
        ./modules/nixos/features/graphics
        ./modules/nixos/features/vscodium
        ./modules/nixos/features/holodeck
        ./modules/nixos/features/containers
    ./modules/hosts/desktop
      ./modules/hosts/desktop/disko.nix
      ./modules/hosts/desktop/hardware-configuration.nix

  nixosConfigurations.wsl
    inputs.nixos-wsl.nixosModules.default
    ./modules/parts.nix
    ./modules/hosts/wsl
```

NixOS combina todos los modulos importados. Las features se importan siempre,
pero su configuracion efectiva queda detras de opciones `enable`. Home Manager
se integra como modulo NixOS y declara la configuracion del usuario
`avivaldelli`.

## Flake

`flake.nix` define:

- `description = "Mi configuracion NixOS"`
- input `nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05"`
- input `home-manager.url = "github:nix-community/home-manager/release-26.05"`
- input `disko.url = "github:nix-community/disko/latest"`
- input `nixos-wsl.url = "github:nix-community/NixOS-WSL/release-26.05"`
- outputs `nixosConfigurations.desktop` y `nixosConfigurations.wsl`
- apps `holodeck` y `disko` para instalaciones
- package `holodeck`, reutilizado por la flake y la feature NixOS
- sistema `x86_64-linux`
- `specialArgs.inputs`, para que `modules/parts.nix` pueda importar modulos
  desde inputs de la flake.

El lockfile fija las revisiones exactas de `nixpkgs`, `home-manager`, `disko` y
`nixos-wsl`.

## Modulos base

`modules/parts.nix` agrupa las partes comunes del sistema:

- `inputs.home-manager.nixosModules.home-manager`
- `./home`
- `./nixos/features`

`modules/nixos/features/default.nix` descubre modulos automaticamente dentro de
`modules/nixos/features`:

- archivos `.nix` regulares, excepto `default.nix`
- directorios que tengan `default.nix`

Esto permite agregar una feature nueva creando un directorio con `default.nix`
sin editar el indice manualmente.

## Hosts

Los hosts viven en `modules/hosts/<nombre>`.

El host `desktop` define:

- bootloader
- layout GPT/EFI/LUKS/ext4 mediante Disko
- red
- locale y timezone
- escritorio
- usuario
- paquetes base
- features activadas
- `system.stateVersion`

`disko.nix` define los filesystems sin UUID efimeros.
`hardware-configuration.nix` queda separado porque contiene modulos de kernel y
datos de CPU especificos de la maquina.

El host `wsl` reutiliza los modulos comunes y Home Manager, pero importa el
modulo oficial de NixOS-WSL y omite hardware configuration, bootloader fisico,
NetworkManager, audio, impresion, GNOME, navegador, drivers, VSCodium Linux y
la VM Windows anidada.

## Frontera de instalacion y estado personal

Los entrypoints `install-desktop.sh` e `install-wsl.sh` son wrappers de
`nix run .#holodeck -- system install`. Holodeck selecciona y valida el flujo,
pero delega los cambios reales:

```text
desktop -> Disko -> nixos-install .#desktop
wsl     -> nixos-rebuild boot .#wsl
```

El layout de disco, bootloader y diferencias de plataforma permanecen en los
hosts NixOS. La autenticacion, llaves y perfiles permanecen en
`holodeck setup` y se ejecutan despues de iniciar sesion como usuario normal.
De este modo un rebuild no regenera credenciales y un onboarding nunca modifica
`/boot`.

## Home Manager

La configuracion interactiva del usuario se arma desde `home/avivaldelli`,
que funciona como identidad local y elige un perfil Home Manager.

- `default.nix`: datos del usuario, `home.stateVersion` e import del perfil.

`modules/home/default.nix` es el puente NixOS hacia Home Manager: define
`home-manager.useGlobalPkgs`, `home-manager.useUserPackages`, backups y el
perfil `home-manager.users.avivaldelli`.

Los perfiles Home Manager viven en `modules/home/profiles`.

- `developer`: shell, starship y AWS. Es el perfil default de `avivaldelli`.
- `minimal`: shell y starship, sin helpers cloud.

Los modulos reutilizables de Home Manager viven en `modules/home/features`.

- `modules/home/features/shell/default.nix`: zsh, aliases, fzf, zoxide y
  direnv. Se activa con `homeFeatures.shell.enable`.
- `modules/home/features/shell/completions.nix`: completions declarativas para
  comandos propios.
- `modules/home/features/starship/default.nix`: prompt. Se activa con
  `homeFeatures.starship.enable`.
- `modules/home/features/aws/default.nix`: `awscli2`, helpers interactivos y
  completions AWS. Se activa con `homeFeatures.aws.enable`.

La diferencia de responsabilidades es:

- NixOS/system: paquetes base, usuarios, servicios, Docker, shells disponibles.
- Home Manager/user: dotfiles, aliases, funciones de shell, prompt y tooling
  interactivo del usuario.

Home Manager usa `useGlobalPkgs = true`, por lo que comparte el mismo `pkgs`
del sistema.

## Features

Convencion actual:

- Las opciones viven bajo `features.<nombre>`.
- Cada feature tiene `enable = lib.mkEnableOption ...`.
- La configuracion se aplica con `lib.mkIf cfg.enable`.
- Los submodulos de una feature viven junto a ella.

Ejemplo minimo:

```nix
{ config, lib, pkgs, ... }:

let
  cfg = config.features.example;
in
{
  options.features.example.enable = lib.mkEnableOption "example feature";

  config = lib.mkIf cfg.enable {
    environment.systemPackages = [ pkgs.hello ];
  };
}
```

## Agregar un host

1. Crear `modules/hosts/<nuevo-host>/default.nix`.
2. Para una maquina fisica, agregar su `hardware-configuration.nix`; para WSL
   u otros entornos virtualizados, importar el modulo de plataforma apropiado.
3. Agregar una salida en `flake.nix`:

```nix
nixosConfigurations.<nuevo-host> = nixpkgs.lib.nixosSystem {
  system = "x86_64-linux";
  specialArgs = {
    inherit inputs;
  };
  modules = [
    ./modules/parts.nix
    ./modules/hosts/<nuevo-host>
  ];
};
```

## Agregar una feature

1. Crear `modules/nixos/features/<feature>/default.nix`.
2. Definir opciones bajo `features.<feature>`.
3. Encapsular efectos con `lib.mkIf cfg.enable`.
4. Activarla desde el host:

```nix
features.<feature>.enable = true;
```

Si la feature necesita archivos auxiliares, dejarlos dentro de su directorio.
