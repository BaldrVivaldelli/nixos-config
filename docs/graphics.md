# Graficos y GPU

La feature vive en `modules/nixos/features/graphics`.

Su objetivo es separar dos cosas:

- configurar graficos de forma declarativa con `features.graphics`
- detectar la GPU local con el helper Python `gpu-doctor`

NixOS no auto-configura drivers desde hardware detectado en cada rebuild. El
host declara que driver quiere usar, y `gpu-doctor` ayuda a elegirlo.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.graphics.enable` | bool | `false` | Activa aceleracion grafica y diagnostico GPU. |
| `features.graphics.driver` | enum | `mesa` | Driver: `mesa`, `amd`, `intel` o `nvidia`. |
| `features.graphics.enable32Bit` | bool | `false` | Habilita librerias graficas de 32 bits para Steam, Wine y juegos viejos. |
| `features.graphics.doctor.enable` | bool | `true` | Instala el comando `gpu-doctor`. |
| `features.graphics.nvidia.open` | bool | `false` | Usa el kernel module abierto de NVIDIA. |
| `features.graphics.nvidia.settings.enable` | bool | `true` | Instala `nvidia-settings`. |
| `features.graphics.nvidia.package` | package | `stable` | Paquete de driver NVIDIA a usar. |

## Uso en desktop

El host `desktop` activa:

```nix
# >>> gpu-doctor graphics
features.graphics = {
  enable = true;
  driver = "amd";
  enable32Bit = false;
};
# <<< gpu-doctor graphics
```

Eso declara explicitamente la GPU AMD detectada por `gpu-doctor`, habilita
`hardware.graphics` e instala `gpu-doctor`.

## Detectar GPU

Despues de aplicar la configuracion:

```bash
gpu-doctor
```

El comando muestra GPUs detectadas por `lspci` y propone un bloque Nix para el
host.

Si se ejecuta desde la raiz del repo, pregunta si queres aplicar la
recomendacion al host y correr:

```bash
sudo nixos-rebuild switch --flake .#desktop
```

Para aplicar sin correr rebuild:

```bash
gpu-doctor --yes --no-rebuild
```

Para recomendar librerias graficas de 32 bits, util para Steam, Wine o juegos
viejos:

```bash
gpu-doctor --gaming
```

Salida JSON:

```bash
gpu-doctor --json
```

## AMD / ATI

Para AMD moderno:

```nix
features.graphics = {
  enable = true;
  driver = "amd";
  enable32Bit = false;
};
```

AMD moderno usa `amdgpu` con Mesa. Placas ATI/Radeon muy viejas pueden requerir
manejo legacy y conviene revisarlas caso por caso.

## Intel

Para Intel:

```nix
features.graphics = {
  enable = true;
  driver = "intel";
  enable32Bit = false;
};
```

El modulo usa el driver `modesetting`.

## NVIDIA

Para NVIDIA:

```nix
features.graphics = {
  enable = true;
  driver = "nvidia";
  enable32Bit = false;

  nvidia = {
    open = false;
  };
};
```

`nvidia.open = false` es el default por compatibilidad amplia. Si la GPU es
Turing o mas nueva, se puede probar:

```nix
features.graphics.nvidia.open = true;
```

En laptops con graficos hibridos, NVIDIA puede necesitar configuracion PRIME
con bus IDs. `gpu-doctor` muestra los bus IDs detectados para usar como punto
de partida.
