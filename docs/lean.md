# Lean

La feature vive en `modules/nixos/features/lean`.

Instala tooling base para proyectos Lean. Por default usa `elan`, porque Lean
suele declarar la version por proyecto con un archivo `lean-toolchain`.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.lean.enable` | bool | `false` | Instala tooling base de Lean. |
| `features.lean.package` | package | `pkgs.elan` | Toolchain manager de Lean. |
| `features.lean.lean4.enable` | bool | `false` | Instala tambien `pkgs.lean4` desde nixpkgs. |

## Uso en desktop

El host `desktop` activa:

```nix
features.lean.enable = true;
```

Eso agrega al perfil del sistema:

- `elan`

Desde ahi, los proyectos Lean pueden resolver su version con `lean-toolchain`.

## Instalar Lean 4 fijo desde nixpkgs

Para tener tambien el paquete `lean4` pinneado por nixpkgs:

```nix
features.lean = {
  enable = true;
  lean4.enable = true;
};
```

## Crear un proyecto rapido

```bash
lake init my-project
cd my-project
lake build
```
