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

Home Manager instala la configuración personal, pero registrar y elegir la
sesión del display manager requiere un rebuild de NixOS. El instalador lo
centraliza:

```bash
./install.sh
# elegir 1) NixOS físico existente: Niri + Home Manager
```

Su equivalente directo es:

```bash
./install.sh existing-nixos
```

El target toma como base `/etc/nixos/configuration.nix`, conserva su import de
`hardware-configuration.nix` y superpone el perfil del repositorio durante el
build. Primero construye el sistema y Home Manager; sólo si ambos pasan ejecuta
los switches. No modifica los archivos de `/etc/nixos` ni guarda su hardware o
almacenamiento en el repo.

Después se cierra la sesión de KDE. SDDM deja Niri preseleccionado y Plasma
permanece disponible como respaldo; no hace falta reiniciar la computadora.

### Integración manual

Si se prefiere administrar el rebuild fuera del instalador, se puede importar
el mismo perfil desde la configuración NixOS existente:

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
