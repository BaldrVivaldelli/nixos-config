# Arquitectura

El repo usa flakes y modulos NixOS. La flake expone una sola configuracion:
`nixosConfigurations.desktop`.

## Import graph

```text
flake.nix
  nixosConfigurations.desktop
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
        ./modules/nixos/features/python
        ./modules/nixos/features/nodejs
        ./modules/nixos/features/graphics
        ./modules/nixos/features/vscodium
        ./modules/nixos/features/holodeck
        ./modules/nixos/features/containers
    ./modules/hosts/desktop
      ./modules/hosts/desktop/hardware-configuration.nix
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
- output `nixosConfigurations.desktop`
- sistema `x86_64-linux`
- `specialArgs.inputs`, para que `modules/parts.nix` pueda importar modulos
  desde inputs de la flake.

El lockfile fija la revision exacta de `nixpkgs` y `home-manager`.

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
- red
- locale y timezone
- escritorio
- usuario
- paquetes base
- features activadas
- `system.stateVersion`

`hardware-configuration.nix` queda separado porque es especifico de la maquina.

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
  direnv.
- `modules/home/features/shell/completions.nix`: completions declarativas para
  comandos propios.
- `modules/home/features/starship/default.nix`: prompt.
- `modules/home/features/aws/default.nix`: `awscli2` y helpers interactivos.

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
2. Agregar su `hardware-configuration.nix`.
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
