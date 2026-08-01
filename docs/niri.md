# Niri

El perfil `developer` instala Niri 26.04 junto con Noctalia. Home Manager parte
del archivo de configuración predeterminado que acompaña a Niri, reemplaza
Waybar por Noctalia y valida el KDL durante cada build.

Atajos principales:

- `Mod+T`: abre Alacritty;
- `Mod+Space`: abre el launcher de Noctalia;
- `Super+Alt+L`: bloquea la sesión con Noctalia;
- `Mod+Shift+/`: muestra el resto de los atajos de Niri.

El perfil también instala `brightnessctl`, `playerctl` y `wireplumber`, usados
por los atajos multimedia incluidos en la configuración base.

## Sesión predeterminada de NixOS

Home Manager instala la configuración personal, pero no puede registrar ni
elegir la sesión del display manager. En un NixOS físico existente, importar el
perfil de sistema sin reemplazar su `hardware-configuration.nix`:

```nix
{
  imports = [
    ./hardware-configuration.nix
    /ruta/al/repo/modules/nixos/profiles/niri-desktop
  ];
}
```

Después se aplica desde la configuración NixOS existente:

```bash
sudo nixos-rebuild switch
```

El perfil habilita Niri, SDDM y selecciona `niri` como sesión predeterminada.
También habilita NetworkManager, Bluetooth, UPower y power-profiles-daemon para
las funciones de sistema de Noctalia. No activa inicio de sesión automático.

Si Plasma ya está declarado, permanece disponible en el selector de SDDM como
sesión de respaldo. Este módulo no contiene discos, UUID, particiones,
bootloader ni una configuración de hardware.

## WSL

Niri y Noctalia se fuerzan a `false` en `#wsl`; una sesión Wayland física no
corresponde a ese host.
