# Desktop Feature

La feature vive en `modules/nixos/features/desktop`.

Configura el entorno grafico base del sistema. Soporta GNOME con GDM o Niri con
SDDM y configuracion XKB.

La carpeta esta separada por entorno para que el host solo elija una opcion y
cada escritorio mantenga su configuracion propia:

```text
modules/nixos/features/desktop/
|-- default.nix
|-- gnome.nix
`-- niri.nix
```

- `default.nix`: opciones comunes e imports.
- `gnome.nix`: GNOME, GDM y configuracion XKB.
- `niri.nix`: Niri, SDDM, sesión predeterminada y servicios para Noctalia.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.desktop.enable` | bool | `false` | Activa escritorio grafico. |
| `features.desktop.environment` | `gnome` o `niri` | `gnome` | Entorno de escritorio. |
| `features.desktop.keyboard.layout` | string | `us` | Layout XKB. |
| `features.desktop.keyboard.variant` | string | `""` | Variante XKB. |

## Ejemplo de uso

Un host gráfico puede activar GNOME:

```nix
features.desktop.enable = true;
```

Eso habilita:

- X server
- GDM
- GNOME
- layout de teclado `us`

Para Niri:

```nix
features.desktop = {
  enable = true;
  environment = "niri";
};
```

La variante Niri habilita SDDM, preselecciona la sesión `niri`, configura los
portales Wayland y activa NetworkManager, Bluetooth, UPower y perfiles de
energía. No habilita autologin y no desactiva otros escritorios ya declarados.

Configuraciones finas de GNOME, dconf, shortcuts y preferencias de usuario
deberian vivir en Home Manager cuando se agreguen.

Para agregar otro entorno, por ejemplo KDE, sumar un modulo dedicado como
`kde.nix`, importarlo desde `default.nix` y agregar el valor correspondiente a
`features.desktop.environment`.
