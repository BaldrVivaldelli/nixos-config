# Contenedores y Windows VM

La feature vive en `modules/nixos/features/containers` y puede habilitar Docker
o Podman. El target `#existing` activa Docker y la subfeature Windows VM; WSL la
mantiene deshabilitada porque usa la integración de Docker Desktop.

## Opciones principales

| Opcion | Default | Descripcion |
| --- | --- | --- |
| `features.containers.enable` | `false` | Activa soporte de contenedores. |
| `features.containers.engine` | `docker` | Runtime: `docker` o `podman`. |
| `features.containers.users` | `[ ]` | Usuarios con acceso al runtime. |
| `features.containers.images` | `images.json` | Imagenes OCI a traer con Nix y cargar en Docker. |

## Docker

Con `engine = "docker"`:

- habilita `virtualisation.docker.enable`
- agrega usuarios configurados al grupo `docker`
- crea el servicio `docker-socket-user-access`
- si hay imagenes declarativas, crea `docker-load-images`

`docker-socket-user-access` aplica ACL de escritura sobre `/run/docker.sock`
para los usuarios configurados. Esto ayuda cuando la sesion todavia no tomo el
grupo `docker`.

## Podman

Con `engine = "podman"`:

- habilita `virtualisation.podman.enable`
- agrega usuarios configurados al grupo `podman`

La carga declarativa de imagenes esta implementada para Docker.

## Imagenes declarativas

`modules/nixos/features/containers/images.json` contiene imagenes pinneadas. Hoy
incluye:

```json
{
  "imageName": "dockurr/windows",
  "imageDigest": "sha256:3633f055f31aadf76bb650b1ca86897ab45b76ad8eb2cf81e86389ace5eb45ac",
  "hash": "sha256-LCtjVYq4vUIpiWxWX9vb1YucWso3nsBX0MBPrSdxeQM=",
  "finalImageName": "dockurr/windows",
  "finalImageTag": "latest"
}
```

Cada entrada puede definir:

- `imageName`
- `imageDigest`
- `hash`
- `finalImageName`
- `finalImageTag`
- `os`
- `arch`
- `tlsVerify`

El servicio `docker-load-images` carga cada imagen con `docker load` y guarda un
marcador bajo `/var/lib/docker-load-images`. Si el marcador coincide con el path
del store y la imagen existe, no la vuelve a cargar.

Comandos utiles:

```bash
systemctl status docker-load-images
sudo systemctl restart docker-load-images
docker image ls
```

## Windows VM

La subfeature vive en `modules/nixos/features/containers/windowsvm`.

Solo aplica cuando:

```nix
features.containers.enable = true;
features.containers.engine = "docker";
features.containers.windowsVm.enable = true;
```

Cuando esta activa:

- carga el modulo kernel `tun`
- instala FreeRDP y elige `sdl-freerdp` en Wayland o `xfreerdp` en X11
- agrega el comando `windowsvm`
- conecta con la imagen declarativa si `features.containers.images` contiene
  la misma referencia que `features.containers.windowsVm.image`

## Opciones de Windows VM

| Opcion | Default |
| --- | --- |
| `image` | `dockurr/windows:latest` |
| `containerName` | `windows` |
| `version` | `11l` |
| `cpuCores` | `2` |
| `ramSize` | `4G` |
| `diskSize` | `64G` |
| `username` | `Docker` |
| `password` | `admin` |
| `language` | `English` |
| `region` | `en-US` |
| `keyboard` | `en-US` |
| `bindAddress` | `127.0.0.1` |
| `webPort` | `8006` |
| `rdpPort` | `3389` |

## Comando windowsvm

```text
windowsvm up [half|fullscreen]  Start the container and open RDP or web viewer
windowsvm start    Start without opening a client
windowsvm rdp [half|fullscreen] Open FreeRDP at the selected size
windowsvm web      Open the Dockurr web viewer
windowsvm status   Show Docker container status
windowsvm logs     Follow logs
windowsvm down     Stop container
windowsvm rm       Stop and remove container
```

Primer arranque:

```bash
windowsvm up
```

Zsh completa tanto el comando como sus subcomandos. Si se acaba de aplicar el
perfil, abrir una terminal nueva o ejecutar `exec zsh` antes de probar
`windowsvm <Tab>`.

Si el contenedor es nuevo, abre el visor web para la instalacion inicial. Cuando
Windows llegue al escritorio:

```bash
windowsvm rdp
```

## Directorios usados

Por defecto:

```text
~/containers/windows/storage
~/containers/windows/shared
```

`shared` se monta dentro de Windows como `C:\Shared`.

Se pueden sobreescribir por entorno:

```bash
WINDOWSVM_STORAGE=/path/storage windowsvm up
WINDOWSVM_SHARED=/path/shared windowsvm up
```

## Variables de entorno

`windowsvm` permite sobreescrituras temporales:

```text
WINDOWSVM_STORAGE
WINDOWSVM_SHARED
WINDOWSVM_VERSION
WINDOWSVM_CPU_CORES
WINDOWSVM_RAM_SIZE
WINDOWSVM_DISK_SIZE
WINDOWSVM_USER
WINDOWSVM_PASSWORD
WINDOWSVM_LANGUAGE
WINDOWSVM_REGION
WINDOWSVM_KEYBOARD
WINDOWSVM_RDP_CLIENT
WINDOWSVM_RDP_DISPLAY_MODE
WINDOWSVM_RDP_TIMEOUT
WINDOWSVM_RDP_ATTEMPTS
```

`WINDOWSVM_RDP_CLIENT` sólo hace falta para diagnóstico o una selección manual;
acepta `sdl-freerdp` y `xfreerdp`. En el uso normal el helper detecta el tipo de
sesión gráfica automáticamente.

`WINDOWSVM_RDP_DISPLAY_MODE` acepta `half` o `fullscreen`. El primero abre la
ventana al 50% del ancho disponible; el segundo usa el monitor completo. Ambos
conservan `dynamic-resolution`, por lo que Windows se adapta si luego cambia el
tamaño de la ventana.

Para cambios permanentes, preferir las opciones Nix en el host.

## Requisitos y troubleshooting

Docker debe estar disponible:

```bash
sudo systemctl start docker
docker info
```

La VM requiere:

- `/dev/kvm`
- `/dev/net/tun`
- imagen Docker cargada
- puertos `8006` y `3389` libres, salvo que se cambien las opciones

Por defecto ambos puertos se publican únicamente en loopback. Cambiar
`bindAddress` sólo cuando se quiera exponer deliberadamente el visor o RDP a
otra interfaz.

Si la sesion todavia no tomo el grupo `docker`, `windowsvm` intenta reejecutarse
con `sg docker`. Si sigue fallando, cerrar sesion y volver a entrar.

Si RDP aun no esta listo:

```bash
windowsvm web
windowsvm logs
```
