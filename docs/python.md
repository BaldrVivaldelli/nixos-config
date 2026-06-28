# Python

La feature vive en `modules/features/python`.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.python.enable` | bool | `false` | Instala tooling base de Python. |
| `features.python.package` | package | `pkgs.python3` | Interprete Python a instalar. |
| `features.python.uv.enable` | bool | `true` | Instala `uv` junto con Python. |

## Uso en desktop

El host `desktop` activa:

```nix
features.python.enable = true;
```

Eso agrega al perfil del sistema:

- `python3`
- `uv`

## Cambiar version o paquete de Python

Desde el host:

```nix
features.python = {
  enable = true;
  package = pkgs.python312;
};
```

## Desactivar uv en un host

```nix
features.python = {
  enable = true;
  uv.enable = false;
};
```

## Crear un proyecto con uv

```bash
uv init my-project
cd my-project
uv add requests
uv run python main.py
```

