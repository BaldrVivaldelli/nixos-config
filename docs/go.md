# Go

La feature `features.go` instala el toolchain de Go en hosts NixOS.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.go.enable` | bool | `false` | Instala el toolchain de Go. |
| `features.go.package` | package | `pkgs.go` | Paquete de Go a instalar. |

## Uso

```nix
features.go.enable = true;
```

El perfil Home Manager `developer` instala `pkgs.go` directamente. El host
NixOS-WSL habilita esta feature para ofrecer el mismo toolchain sin instalar
las aplicaciones graficas del perfil.

## Cambiar el paquete

```nix
features.go = {
  enable = true;
  package = pkgs.go_1_24;
};
```
