# Git

La feature vive en `modules/nixos/features/git`.

Instala tooling Git de sistema sin escribir `~/.gitconfig`. Las identidades,
perfiles, SSH y GPG siguen siendo responsabilidad de Holodeck.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.git.enable` | bool | `false` | Instala tooling Git. |
| `features.git.package` | package | `pkgs.git` | Paquete Git a instalar. |
| `features.git.lfs.enable` | bool | `true` | Instala Git LFS. |
| `features.git.delta.enable` | bool | `true` | Instala delta para diffs enriquecidos. |
| `features.git.lazygit.enable` | bool | `true` | Instala lazygit. |

## Uso en desktop

El host `desktop` activa:

```nix
features.git.enable = true;
```

Eso instala:

- `git`
- `git-lfs`
- `delta`
- `lazygit`

## Relacion con Holodeck

Holodeck configura perfiles locales de Git, SSH y GPG. Esta feature no define
`programs.git` ni escribe `~/.gitconfig` para no pelearse con los bloques
manejados por Holodeck.
