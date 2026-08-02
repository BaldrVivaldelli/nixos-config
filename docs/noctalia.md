# Noctalia

El perfil `developer` instala Noctalia v5 mediante su módulo oficial de Home
Manager. La entrada queda fijada en `flake.lock` y usa por defecto el tema
builtin `Catppuccin` en modo oscuro. El IR local puede cambiar el modo a claro
sin convertir la interfaz en una segunda fuente de verdad.

```nix
homeFeatures.noctalia.enable = true;
```

## Integración con Niri

El perfil `developer` también habilita `homeFeatures.niri`. La configuración de
Niri inicia `noctalia` automáticamente, conecta su launcher y lock screen, y
aplica las reglas de ventana recomendadas para su panel de configuración.

Para iniciarla manualmente durante una prueba:

```bash
noctalia
```

Noctalia y Niri quedan forzadas a `false` en el host WSL porque allí no hay una
sesión Wayland de escritorio.

## Plugin Holodeck Control

Home Manager instala el plugin `holodeck/control` desde un path inmutable
del Nix store, lo habilita en `config.toml` y agrega una entrada XDG llamada
`Holodeck Control`. La fuente local implícita conserva las fuentes `official` y
`community` de Noctalia.

Para abrirlo:

```bash
# Desde el launcher de Noctalia: Mod+Space y buscar "Holodeck Control"
noctalia msg panel-toggle holodeck/control:control
```

El frontend Luau sólo elige valores enumerados, consulta estado y pide una
confirmación. `holodeckctl` valida y escribe `holodeck.local.json`; el panel
nunca genera código Nix ni ejecuta el `argv` devuelto por el plan. Los builds y
switches se abren en una terminal para mantener visibles logs y pedidos de
privilegios.

El panel sigue la jerarquía visual de Noctalia: usa una barra lateral compacta
como la del Control Center y divide el uso en **Resumen**, **Sistema** e
**Integraciones**. Esta última vista muestra un proveedor por vez para evitar
una pantalla larga y saturada. Para los providers sólo lee nombres, host y
disponibilidad; la autenticación, las claves y las credenciales siguen en
`holodeck`, AWS CLI y `windowsvm`. Cada acción se abre en una terminal y al
volver se actualiza con el botón de recarga del encabezado.

La UI de Noctalia puede guardar un override que deshabilite un plugin. Home
Manager garantiza que esté instalado y habilitado en la configuración base,
pero no borra ese estado global porque también contiene preferencias de otros
plugins.

El contrato completo está en [holodeck-control.md](holodeck-control.md).

## Servicios de NixOS

Algunas funciones de la shell requieren servicios del sistema, entre ellos
NetworkManager, Bluetooth, UPower y un daemon de perfiles de energía. El perfil
reutilizable `modules/nixos/profiles/niri-desktop` habilita esos servicios sin
administrar discos ni reemplazar el hardware config del sistema existente.
