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
- si hay imagenes declarativas, crea `docker-load-images`

El acceso usa únicamente la membresía normal del grupo `docker`; no se agregan
ACL paralelas sobre `/run/docker.sock`. Después de aplicar el sistema hay que
cerrar y volver a abrir la sesión para tomar el grupo.

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
  "finalImageTag": "latest",
  "runtimeTag": "nixos-3633f055f31a"
}
```

Cada entrada puede definir:

- `imageName`
- `imageDigest`
- `hash`
- `finalImageName`
- `finalImageTag`
- `runtimeTag`
- `os`
- `arch`
- `tlsVerify`

El servicio `docker-load-images` obtiene del archive el ID exacto de la imagen,
la carga, aplica el `runtimeTag` estable y verifica identidad antes de escribir
el marcador bajo `/var/lib/docker-load-images`. Un tag existente que apunte a
otro ID no se acepta como válido.

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
| `image` | `dockurr/windows:nixos-3633f055f31a` |
| `containerName` | `windows` |
| `version` | `11l` |
| `cpuCores` | `2` |
| `ramSize` | `4G` |
| `diskSize` | `64G` |
| `username` | `Docker` |
| `language` | `English` |
| `region` | `en-US` |
| `keyboard` | `en-US` |
| `bindAddress` | `127.0.0.1` |
| `allowRemoteAccess` | `false` |
| `webPort` | `8006` |
| `rdpPort` | `3389` |

## Comando windowsvm

Al migrar desde la configuración anterior hay que eliminar cualquier opción
Nix `windowsVm.password`. La primera creación pide la password una sola vez;
también puede recibirla mediante `WINDOWSVM_PASSWORD_FILE`. Un contenedor
existente migra la credencial que Docker ya conserva después de una
autenticación exitosa y se reutiliza sólo si su image ID coincide con el archive
fijado; si no coincide, `windowsvm` lo rechaza y muestra el comando explícito
para recrearlo sin borrar automáticamente su storage.

```text
windowsvm up [half|fullscreen]  Start the container and open RDP or web viewer
windowsvm start    Start without opening a client
windowsvm rdp [half|fullscreen] Open FreeRDP at the selected size
windowsvm web      Open the Dockurr web viewer
windowsvm unlock   Unlock the local Windows account and restart
windowsvm password-reset  Replace the local Windows password and restart
windowsvm wipe     Delete the Windows guest disk and create a fresh VM
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

Si el contenedor es nuevo, abre el visor web para mostrar la instalación
inicial, espera hasta que Dockurr informe que Windows arrancó correctamente,
realiza una preparación RDP única y abre FreeRDP automáticamente. No hace falta
volver a ejecutar otro comando al llegar al escritorio.

## Directorios usados

Por defecto:

```text
~/containers/windows/storage
~/containers/windows/storage/.windowsvm-credentials.json
~/containers/windows/shared
~/containers/windows/storage-backups
```

`shared` se monta dentro de Windows como `C:\Shared`. El archivo oculto de
credenciales pertenece al usuario, usa modo `0600`, nunca entra al repo y se
elimina junto con el guest mediante `windowsvm wipe`. No se muestra ni se carga
en el panel: `windowsvm` lo consume directamente.

`storage-backups` recibe una copia sparse de `data.img` antes de cada desbloqueo
o reemplazo de password. Esa copia contiene el estado anterior de Windows: el
helper la elimina automáticamente sólo después de que Windows acepta la
credencial por RDP; si la validación falla o se interrumpe, conserva la ruta
para recovery.

Se pueden sobreescribir por entorno:

```bash
WINDOWSVM_STORAGE=/path/storage windowsvm up
WINDOWSVM_SHARED=/path/shared windowsvm up
WINDOWSVM_BACKUP_DIR=/path/backups windowsvm password-reset
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
WINDOWSVM_PASSWORD_FILE
WINDOWSVM_BACKUP_DIR
WINDOWSVM_LANGUAGE
WINDOWSVM_REGION
WINDOWSVM_KEYBOARD
WINDOWSVM_RDP_CLIENT
WINDOWSVM_RDP_DISPLAY_MODE
WINDOWSVM_RDP_TIMEOUT
WINDOWSVM_RDP_ATTEMPTS
WINDOWSVM_INSTALL_TIMEOUT
WINDOWSVM_ACCOUNT_UNLOCK_TIMEOUT
WINDOWSVM_PASSWORD_RESET_TIMEOUT
WINDOWSVM_WIPE_CONFIRM
```

## Acceso automático y desbloqueo de la cuenta RDP

La primera ejecución administrada guarda la credencial y marca la política RDP
del guest como pendiente. Cuando Windows queda disponible, `windowsvm up`
detiene la VM una sola vez, crea una copia sparse, programa como `SYSTEM` el
desbloqueo de la cuenta y configura `Account lockout threshold = 0`. Microsoft
documenta que [ese valor evita que la cuenta vuelva a bloquearse](https://learn.microsoft.com/en-us/previous-versions/windows/it-pro/windows-10/security/threat-protection/security-policy-settings/account-lockout-threshold).
En este perfil
la decisión se limita a una VM personal cuyos puertos RDP y web están enlazados
a `127.0.0.1`; no debe combinarse con `allowRemoteAccess` sin reevaluar la
política de fuerza bruta.

Después de validar RDP, la credencial pasa a schema 2 con
`rdpPolicyVersion = 1`, se elimina la copia temporal y las aperturas siguientes
sólo inician Windows y FreeRDP. Holodeck informa el estado sin devolver la
password, oculta los inputs y presenta un único botón **Abrir Windows**. Una VM
nueva puede esperar hasta `WINDOWSVM_INSTALL_TIMEOUT` —3600 segundos por
default— sin pedir otro clic.

`windowsvm unlock` conserva la contraseña y desbloquea la cuenta local indicada
por `WINDOWSVM_USER`. Detiene limpiamente la VM, crea una copia sparse
recuperable de `data.img`, programa una acción de primer arranque como `SYSTEM`
y vuelve a iniciar Windows. La acción usa el proveedor ADSI WinNT para establecer
`IsAccountLocked = false`, que es el mecanismo de desbloqueo documentado por
[Microsoft](https://learn.microsoft.com/es-es/windows/win32/adsi/winnt-account-lockout).

La contraseña guardada —o una sobreescritura explícita— sólo se usa después del
arranque para validar las credenciales por RDP. Un rechazo explícito detiene la
validación sin reintentos automáticos, evitando volver a bloquear la cuenta. Si
la validación funciona se elimina la copia temporal; si falla, se conserva para
recovery. Este comando queda disponible como reparación avanzada de CLI; el
flujo normal de Holodeck lo ejecuta automáticamente cuando hace falta.

Sólo puede ejecutarse un lanzamiento u operación de mantenimiento (`up`, `rdp`,
`unlock`, `password-reset` o `wipe`) a la vez. Un lock privado en
`XDG_RUNTIME_DIR` rechaza clics duplicados antes de que puedan detener Windows o
abrir dos sesiones. La
validación `auth-only` también tiene un límite duro: si FreeRDP confirma éxito
pero queda colgado al cerrar, el helper acepta la validación y termina el
proceso; este workaround evita dejar Holodeck esperando indefinidamente.

## Reemplazo de la password de Windows

Las variables `USERNAME` y `PASSWORD` de Dockurr configuran la cuenta durante
la instalación inicial; cambiar sólo el metadata de un contenedor existente no
modifica una cuenta ya instalada. `windowsvm password-reset` cubre ese caso:

1. detiene limpiamente la VM;
2. crea una copia sparse recuperable de `data.img` fuera del directorio montado;
3. usa `virt-customize --firstboot` para inyectar un batch de un solo uso que
   ejecuta `Set-LocalUser` y limpia el bloqueo de la cuenta como SYSTEM en el
   siguiente arranque; el ejecutor
   `rhsrvany.exe` se construye de forma reproducible desde el nixpkgs fijado;
4. elimina sólo el contenedor Docker anterior, no el storage;
5. lo recrea con `USERNAME` y `PASSWORD` actuales y vuelve a iniciar Windows;
6. valida la password exacta con FreeRDP en modo `auth-only`; ante un rechazo
   explícito no reintenta, ante éxito elimina la copia anterior y ante timeout
   la conserva sin afirmar que el cambio quedó aplicado.

La vista Windows de Holodeck mantiene esta operación dentro de **Cambiar
credencial o borrar la VM**, fuera del recorrido normal. Usa exactamente la
nueva password escrita y una segunda confirmación. La operación se muestra en
una terminal porque copiar y editar el disco puede tardar. El script de primer
arranque no se reintenta en bucle si PowerShell falla; en ese caso la terminal
conserva la ruta de la copia para recuperación.

Dockurr documenta `USERNAME` y `PASSWORD` como opciones de instalación en su
[README oficial](https://github.com/dockur/windows). `virt-customize` requiere
la VM apagada y ejecuta `--firstboot` dentro del guest según su
[manual oficial](https://libguestfs.org/virt-customize.1.html).

## WIPE WindowsVM

El panel expone **WIPE WindowsVM** dentro de la gestión avanzada como una
operación separada e irreversible. Usa exactamente el usuario y password nuevos
de los inputs y exige escribir `WIPE` en una segunda confirmación. El backend
además requiere internamente
`WINDOWSVM_WIPE_CONFIRM=WIPE` antes de aceptar el comando.

El wipe valida primero Docker, KVM, la imagen runtime y que el storage sea un
directorio Dockurr propiedad del usuario. Después:

1. detiene y elimina sólo el contenedor anterior;
2. mueve atómicamente el storage viejo a una ruta de cuarentena hermana;
3. crea un storage vacío y un contenedor nuevo con las credenciales ingresadas;
4. si la creación falla, elimina el intento y restaura el storage original;
5. si Docker acepta el contenedor nuevo, elimina definitivamente la cuarentena
   y abre el visor Web para seguir Windows Setup.

Se eliminan `data.img` y todos los metadatos del guest dentro de `storage`: se
pierden Windows, programas y archivos internos. `shared` queda intacto. Tampoco
se borra la imagen Docker fijada por Nix, porque es el runtime reproducible que
se reutiliza para crear la instalación nueva.

Por CLI la misma protección requiere una confirmación explícita:

```bash
WINDOWSVM_WIPE_CONFIRM=WIPE windowsvm wipe
```

`WINDOWSVM_PASSWORD_FILE` y `WINDOWSVM_PASSWORD` son sobreescrituras explícitas.
Si no se definen, `windowsvm` usa el archivo privado asociado al storage; para
contenedores anteriores puede leer inicialmente el mismo valor que Docker ya
conserva en `Config.Env`. Si tampoco existe, pide la credencial con un prompt
silencioso. Holodeck sólo muestra los campos durante el onboarding o al abrir la
gestión avanzada; después los mantiene ocultos y reutiliza la copia sin
mostrarla. Un valor nuevo se entrega como solicitud efímera de un solo uso.
`password-reset` y `wipe` no aceptan la copia implícita: requieren escribir una
nueva password. No existe una password Nix por default.

`WINDOWSVM_RDP_CLIENT` sólo hace falta para diagnóstico o una selección manual;
acepta `sdl-freerdp` y `xfreerdp`. En el uso normal el helper detecta el tipo de
sesión gráfica automáticamente.

`WINDOWSVM_RDP_DISPLAY_MODE` acepta `half` o `fullscreen`. El primero abre la
ventana al 50% del ancho disponible; el segundo usa el monitor completo. Ambos
conservan `dynamic-resolution`, por lo que Windows se adapta si luego cambia el
tamaño de la ventana. En Niri, una regla específica evita el auto-floating de
FreeRDP y coloca el modo `half` como una columna normal del layout. El cliente
se inicia además con `-decorations`, por lo que la columna no muestra la barra
de título local de FreeRDP. El helper usa sólo `dynamic-resolution`: FreeRDP 3
rechaza combinarla con `smart-sizing`, por lo que esa opción no se envía.

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

Por defecto ambos puertos se publican únicamente en loopback. Otro
`bindAddress` falla durante la evaluación salvo que también se declare
`allowRemoteAccess = true`; ese opt-in sólo debe usarse con controles de red y
credenciales adecuados.

Si la sesion todavia no tomo el grupo `docker`, `windowsvm` intenta reejecutarse
con `sg docker`. Si sigue fallando, cerrar sesion y volver a entrar.

Si RDP aun no esta listo:

```bash
windowsvm web
windowsvm logs
```
