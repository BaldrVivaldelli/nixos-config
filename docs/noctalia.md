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

## Wallpapers

Noctalia usa `~/Pictures/Wallpaper` como biblioteca local y
`nave-wallpaper.png` como fondo predeterminado. La barra incluye tres accesos:

- El selector nativo `wallpaper`, que busca por nombre dentro de la biblioteca
  local. También se puede abrir con `Mod+Space` y el prefijo `/wall`.
- El plugin `noctalia/wallhaven`, con un filtro SFW obligatorio aplicado por Nix,
  que permite buscar, previsualizar, descargar y aplicar imágenes de Wallhaven.
  Las descargas quedan disponibles también en el selector local.
- `nzlov/daily-wallpaper`, con un panel para elegir **Bing** o **NASA**,
  previsualizar su imagen del día y aplicarla manualmente.

Los cambios hechos desde la UI o mediante `noctalia msg wallpaper-set` se
guardan en el estado local de Noctalia y pueden reemplazar el fondo
predeterminado sin modificar el repositorio. Una imagen propia se aplica con:

```bash
noctalia msg wallpaper-set "$HOME/Pictures/Wallpaper/mi-fondo.png"
```

Wallhaven funciona sin API key para búsquedas normales. Una clave opcional se
debe ingresar sólo en la configuración local del plugin y nunca en el repo.

La variante local fija `purity=100` en todas las búsquedas y descarta resultados
`sketchy`, `nsfw` o sin clasificación antes de mostrar o descargar miniaturas.
El panel no ofrece controles para habilitar contenido sugerente o adulto, aunque
haya una API key. Usa una caché separada para las miniaturas filtradas.

Home Manager instala esta variante desde una revisión fija del plugin oficial.
La fuente local tiene prioridad sobre el catálogo remoto, de modo que actualizar
plugins desde Noctalia no elimina el filtro. Las pruebas del paquete comprueban
las peticiones y el descarte de resultados antes de descargar imágenes.
El filtro depende de la clasificación de Wallhaven: no analiza visualmente las
imágenes que el proveedor haya etiquetado erróneamente como SFW.

Bing y NASA usan exclusivamente sus feeds editoriales oficiales del día. No son
buscadores abiertos ni devuelven clasificaciones de edad: no existe un filtro
SFW equivalente para ellos. La variante local acepta sólo imágenes del endpoint
editorial de Bing o de dominios HTTPS de NASA, y rechaza URLs ajenas. Esta
restricción sobre las fuentes no constituye un análisis visual del contenido.

El plugin del día está fijado en Nix y tiene prioridad sobre el catálogo remoto.
Habilitarlo, cambiar de fuente o refrescar una vista nunca cambia el fondo por
sí solo: hace falta pulsar **Aplicar fondo**. Las imágenes descargadas se guardan
en `~/Pictures/Wallpaper/daily-wallpaper` y no se borran automáticamente.
Desde el panel abierto, seleccionar fuente y aplicar requiere dos clics.

Los demás plugins de fondos del catálogo trabajan con archivos locales, vídeos
o una biblioteca de Wallpaper Engine ya descargada desde Steam; no agregan
otros buscadores online a esta instalación.

## Providers del launcher

Los providers nativos quedan declarados en Nix con prefijos estables:

- `/calc` para cálculos y conversiones.
- `/emo` para buscar emojis.
- `/session` para acciones de sesión.
- `/wall` para buscar wallpapers locales.
- `/win` para buscar y enfocar ventanas abiertas.

La calculadora participa además en la búsqueda global; los demás providers se
activan sólo con su prefijo para mantener el launcher limpio. Wallhaven no es
un provider del launcher: es un plugin oficial con panel y botón propios, y
también queda habilitado declarativamente.

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
`holodeck`, AWS CLI y `windowsvm`. AWS presenta una sola acción que inicia SSO
y descubre todas las cuentas y roles asignados. Cada combinación genera por
defecto dos perfiles, uno en `us-east-1` y otro en `us-east-2`. El editor permite
conservar ambos, dejar sólo uno o agregar otras regiones; cada región produce
su propio sufijo y los alias pueden recomendarse individualmente o en conjunto.
Las acciones interactivas se abren en una terminal y al volver se actualizan con
el botón de recarga del encabezado. Los lanzadores gráficos RDP y Web se abren
directamente desde el panel.

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
