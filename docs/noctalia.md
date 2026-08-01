# Noctalia

El perfil `developer` instala Noctalia v5 mediante su módulo oficial de Home
Manager. La entrada queda fijada en `flake.lock` y configurada con el tema
oscuro builtin `Catppuccin`.

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

## Servicios de NixOS

Algunas funciones de la shell requieren servicios del sistema, entre ellos
NetworkManager, Bluetooth, UPower y un daemon de perfiles de energía. El perfil
reutilizable `modules/nixos/profiles/niri-desktop` habilita esos servicios sin
administrar discos ni reemplazar el hardware config del sistema existente.
