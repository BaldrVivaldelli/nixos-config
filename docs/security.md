# Seguridad y secretos

Este repo no debe contener secretos. La configuracion declarativa puede referir
a herramientas y rutas, pero tokens, llaves privadas, credenciales y material
sensible deben vivir fuera del repo.

## Archivos ignorados

`.gitignore` bloquea, entre otros:

- outputs de Nix como `result`
- caches locales
- archivos `.env`, credenciales cloud y estado de autenticación local
- `.ssh`, `.gnupg`, llaves privadas, keyrings y perfiles VPN
- tokens, passwords, estados de Terraform y copias de respaldo
- directorios `secrets`, `private`, `.secrets`, `.private`
- estado generado por Holodeck bajo `.config/holodeck`
- inventario de máquina `inventory.local.nix`
- IR declarativo local `holodeck.local.json` y su lock
- caches de Python y Node.js

`holodeck.local.json` no contiene comandos ni secretos: sólo enums y valores de
apariencia validados. Aun así queda fuera de Git porque expresa la intención de
una máquina concreta.

Holodeck Control sólo devuelve al frontend nombres de perfil, proveedor y host.
No devuelve emails, rutas de claves, fingerprints, tokens, passwords ni el
contenido de archivos AWS. Sus acciones se ejecutan en una terminal mediante
un enum cerrado y listas de argumentos, nunca mediante comandos construidos con
datos recibidos desde Luau.

## Escaneo automático

El perfil de Home Manager instala `detect-secrets` y configura automáticamente:

```bash
git config --local core.hooksPath .githooks
```

El hook versionado analiza los archivos stageados y bloquea paths sensibles,
llaves privadas, passwords, tokens y claves de proveedores conocidos. Si el
detector no está disponible, el commit falla de forma cerrada.

`nix flake check` ejecuta además `secret-scan` sobre todo el source, incluso si
alguien omitió el hook con `--no-verify`. `.secrets.baseline` contiene solamente
hashes de falsos positivos revisados —digests Nix de imágenes y extensiones—,
nunca los valores en texto plano. Tanto el hook como el check excluyen ese
archivo del escaneo heurístico para que el detector no confunda sus propios
hashes con secretos.

Ningún detector heurístico puede reconocer literalmente cualquier secreto. Si
un secreto real llegó a un commit, agregarlo a `.gitignore` o borrarlo después
no lo quita del historial: hay que revocarlo o rotarlo inmediatamente y limpiar
el historial publicado.

## Holodeck

Holodeck esta pensado para mantener credenciales fuera de Git:

- perfiles en `~/.config/holodeck`
- llaves SSH en `~/.ssh/holodeck_*`
- llaves GPG en el keyring local
- auth de GitHub/GitLab manejada por `gh` y `glab`

`holodeck purge` elimina el estado local que Holodeck conoce, pero no borra
llaves publicas ya subidas a GitHub o GitLab.

## AWS

Home Manager instala `awscli2` y helpers de shell. Holodeck puede generar
perfiles no secretos dentro de un bloque delimitado de `~/.aws/config`, pero no
escribe tokens ni credenciales: éstos siguen en el cache local de AWS CLI bajo
`~/.aws/sso/cache`, el navegador o el keyring usado por AWS SSO. Al
resincronizar se reemplaza sólo el bloque administrado y se preservan las demás
secciones de configuración. La URL y región SSO no se incluyen en el
inventario ni en el paquete Nix: se obtienen de la configuración AWS local o se
piden durante la primera sincronización.

Los alias y regiones confirmadas desde Holodeck se guardan sólo en
`~/.config/holodeck/aws-aliases.json`. El archivo contiene claves opacas y esas
preferencias, no tokens, URLs ni IDs de cuenta. Noctalia escribe un borrador
transitorio en su directorio local de estado; el backend valida todas las
claves y valores, regenera el bloque AWS y elimina el borrador al completar la
operación.

## Frontera de evaluación Nix

Los entrypoints no evalúan `path:.` sobre el checkout completo. Preparan un
snapshot con los archivos versionados actuales y un allowlist explícito de
`inventory.local.nix` y `holodeck.local.json`. Así `.git`, caches, outputs y
otros ignorados no se copian al Nix store. `./prepare-flake-source.sh --check`
aplica la misma regla a la validación manual.

## Windows VM

La password de Windows/RDP no es una opción Nix ni tiene default. En la primera
creación `windowsvm` la lee de `WINDOWSVM_PASSWORD_FILE`, de
`WINDOWSVM_PASSWORD` o de un prompt silencioso. Después de crear la VM o de una
autenticación RDP exitosa, guarda usuario y password en
`$WINDOWSVM_STORAGE/.windowsvm-credentials.json`, propiedad del usuario y modo
`0600`. El schema 2 agrega únicamente una versión de la política RDP aplicada.
El archivo se reemplaza atómicamente, se rechazan symlinks, tipos
inesperados, ownership ajeno, permisos más amplios y JSON con campos extra. Un
contenedor anterior sin archivo migra su `Config.Env` sólo a través del mismo
flujo y la copia se consolida tras una autenticación válida.

El backend de status abre la copia con `O_NOFOLLOW`, valida schema, ownership y
modo, y sólo devuelve `credentialStored`, el username no secreto y la versión
de resiliencia; nunca serializa la password. El frontend no lee ni muestra el
archivo y oculta los inputs una vez configurado. Si el usuario escribe una
credencial durante el onboarding o la gestión avanzada, crea una solicitud de
un solo uso en el `XDG_RUNTIME_DIR` privado; el backend la abre sin seguir
symlinks, la elimina antes de lanzar `windowsvm` y nunca la incluye en argv, el
IR o el repo. Las credenciales explícitas sólo sustituyen la copia después de
una creación o autenticación exitosa, de modo que un typo no sobreescribe el
secreto válido. `password-reset` y `WIPE` siempre exigen una password nueva
explícita.

La acción explícita de reemplazo toma el valor del mismo textbox, detiene la VM,
crea una copia sparse recuperable y programa un `Set-LocalUser` de primer
arranque sobre el disco existente. El script host vive en un directorio privado
temporal, la password viaja codificada dentro del batch de un solo uso y
`virt-customize --no-logfile --no-network` evita log de build y red. Al recrear
el contenedor, `docker run` recibe las variables mediante un env-file privado
efímero, no por argv. Docker conserva la password vigente en `Config.Env` del
contenedor por contrato de Dockurr. La validación final usa FreeRDP `auth-only`
con argumentos por stdin: si Windows acepta exactamente la nueva credencial se
actualiza el archivo privado y elimina la copia que contiene el estado anterior;
si falla o vence el timeout, conserva ambos estados anteriores para recovery y
la operación termina con error.

La preparación automática y la acción avanzada de desbloqueo no cambian la
password. Con la VM detenida crean la misma clase de copia recuperable y
programan como `SYSTEM` un cambio ADSI WinNT `IsAccountLocked = false` junto con
`Account lockout threshold = 0`; luego validan la credencial privada o la
sobreescritura efímera por RDP. Esta política evita bloqueos futuros pero reduce
la defensa del guest ante fuerza bruta, por lo que sólo se aplica al perfil
local con RDP enlazado a `127.0.0.1`. Los rechazos explícitos de autenticación no
se reintentan automáticamente.

Los lanzamientos y operaciones offline comparten un lock no bloqueante dentro
del `XDG_RUNTIME_DIR` privado y validado del usuario. Esto impide que dos clics
abran sesiones duplicadas o que un desbloqueo, reemplazo o WIPE edite el mismo
disco mientras se inicia. Cada intento `auth-only` está además envuelto en un
timeout con terminación forzada;
si FreeRDP registra éxito pero no sale, el helper reconoce ese estado sin
repetir la autenticación.

`WIPE WindowsVM` tiene una frontera distinta: es irreversible una vez creado el
contenedor nuevo. El panel exige escribir `WIPE`; el backend agrega un marcador
cerrado y `windowsvm` vuelve a validarlo. Antes de borrar, el helper rechaza
symlinks, rutas amplias o sensibles, storage ajeno y directorios que no tengan
los marcadores de Dockurr. El storage viejo se mueve a una cuarentena hermana y
se restaura si falla la creación inicial. `shared` y la imagen runtime de Nix no
forman parte del borrado. El archivo privado sí vive dentro de `storage`, por lo
que se elimina con el guest y la VM nueva vuelve a requerir una password
explícita.

La imagen runtime tiene un tag local estable y su ID se compara con el config
digest del archive fijado por Nix antes de crear o arrancar el contenedor. Un
contenedor existente con otra identidad se rechaza en vez de arrancarse.

Los puertos web y RDP usan `features.containers.windowsVm.bindAddress =
"127.0.0.1"` por default. Cualquier otro valor requiere además el opt-in
`features.containers.windowsVm.allowRemoteAccess = true`; no habilitarlo sin
controles de red y credenciales adecuadas.

El modo de pantalla RDP guardado en el IR es un enum cerrado (`half` o
`fullscreen`). `holodeckctl` lo valida antes de pasarlo como argumento a
`windowsvm`; el frontend no construye comandos ni acepta resoluciones libres.

## Reglas practicas

- No commitear tokens, passwords ni llaves privadas.
- No guardar `.env` reales en el repo.
- No commitear exports privados de GPG.
- No regenerar `.secrets.baseline` a ciegas para silenciar un hallazgo.
- Usar un secret manager o archivos locales ignorados por Git.
- Si un secreto fue commiteado, rotarlo. Borrarlo del commit no alcanza si ya
  fue publicado.
