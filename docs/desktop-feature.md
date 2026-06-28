# Desktop Feature

La feature vive en `modules/nixos/features/desktop`.

Configura el entorno grafico base del sistema. Por ahora soporta GNOME con GDM
y configuracion XKB.

La carpeta esta separada por entorno para que el host solo elija una opcion y
cada escritorio mantenga su configuracion propia:

```text
modules/nixos/features/desktop/
|-- default.nix
`-- gnome.nix
```

- `default.nix`: opciones comunes e imports.
- `gnome.nix`: GNOME, GDM y configuracion XKB actual.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.desktop.enable` | bool | `false` | Activa escritorio grafico. |
| `features.desktop.environment` | enum | `gnome` | Entorno de escritorio. |
| `features.desktop.keyboard.layout` | string | `us` | Layout XKB. |
| `features.desktop.keyboard.variant` | string | `""` | Variante XKB. |

## Uso en desktop

El host `desktop` activa:

```nix
features.desktop.enable = true;
```

Eso habilita:

- X server
- GDM
- GNOME
- layout de teclado `us`

Configuraciones finas de GNOME, dconf, shortcuts y preferencias de usuario
deberian vivir en Home Manager cuando se agreguen.

Para agregar otro entorno, por ejemplo Niri o KDE, sumar un modulo dedicado
como `niri.nix` o `kde.nix`, importarlo desde `default.nix` y agregar el valor
correspondiente a `features.desktop.environment`.
