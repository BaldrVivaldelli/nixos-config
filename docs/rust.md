# Rust

La feature `features.rust` instala el compilador de Rust y Cargo en hosts
NixOS.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.rust.enable` | bool | `false` | Instala tooling base de Rust. |
| `features.rust.package` | package | `pkgs.rustc` | Compilador de Rust a instalar. |
| `features.rust.cargo.enable` | bool | `true` | Instala Cargo junto con Rust. |

## Uso

```nix
features.rust.enable = true;
```

El perfil Home Manager `developer` instala `pkgs.rustc` y `pkgs.cargo`
directamente. El host NixOS-WSL habilita esta feature para ofrecer el mismo
toolchain sin instalar las aplicaciones graficas del perfil.

## Cambiar el compilador

```nix
features.rust = {
  enable = true;
  package = pkgs.rustc;
  cargo.enable = true;
};
```
