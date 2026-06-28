# Arquitectura

El repo usa flakes y modulos NixOS. La flake expone una sola configuracion:
`nixosConfigurations.desktop`.

## Import graph

```text
flake.nix
  nixosConfigurations.desktop
    ./modules/parts.nix
      ./modules/features/default.nix
        ./modules/features/python
        ./modules/features/vscodium
        ./modules/features/holodeck
        ./modules/features/containers
    ./modules/hosts/desktop
      ./modules/hosts/desktop/hardware-configuration.nix
```

NixOS combina todos los modulos importados. Las features se importan siempre,
pero su configuracion efectiva queda detras de opciones `enable`.

## Flake

`flake.nix` define:

- `description = "Mi configuracion NixOS"`
- input `nixpkgs.url = "github:NixOS/nixpkgs/nixos-26.05"`
- output `nixosConfigurations.desktop`
- sistema `x86_64-linux`

El lockfile fija la revision exacta de `nixpkgs`.

## Modulos base

`modules/parts.nix` importa `./features`.

`modules/features/default.nix` descubre modulos automaticamente dentro de
`modules/features`:

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
  modules = [
    ./modules/parts.nix
    ./modules/hosts/<nuevo-host>
  ];
};
```

## Agregar una feature

1. Crear `modules/features/<feature>/default.nix`.
2. Definir opciones bajo `features.<feature>`.
3. Encapsular efectos con `lib.mkIf cfg.enable`.
4. Activarla desde el host:

```nix
features.<feature>.enable = true;
```

Si la feature necesita archivos auxiliares, dejarlos dentro de su directorio.
