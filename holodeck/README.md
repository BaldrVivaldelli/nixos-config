# Holodeck

<p align="center">
  <img src="../plugins/noctalia/holodeck-control/assets/holodeck-control.png" width="160" alt="Holodeck: cámara de simulación holográfica">
</p>

Holodeck es un asistente portable para preparar identidades de desarrollo y
mantener separados los perfiles personales y laborales de Git, SSH, GitHub y
GitLab.

El proyecto puede usarse desde la terminal sin NixOS, Home Manager, Noctalia ni
la Windows VM. Esas piezas son integraciones opcionales mantenidas por el
repositorio que actualmente hospeda el proyecto.

## Qué resuelve

- configura identidades Git distintas según el árbol de proyectos;
- autentica GitHub y GitLab mediante sus clientes oficiales;
- crea una clave SSH Ed25519 independiente para cada perfil;
- valida la conexión SSH antes de activar una configuración;
- permite habilitar firma GPG por perfil;
- comprueba autenticación, claves y enrutamiento con `holodeck doctor`;
- puede retirar únicamente el estado que administra con `holodeck purge`.

Holodeck usa reglas `includeIf` de Git. Por ejemplo, un repositorio dentro de
`~/projects/personal` puede usar la identidad de GitHub y otro dentro de
`~/projects/work` la identidad de GitLab, sin cambiar la configuración a mano.

## Arquitectura

```text
holodeck/
├── core/                    # CLI portable y lógica de identidades
│   ├── holodeck/
│   ├── tests/
│   └── pyproject.toml
└── backends/                # instaladores de sistema opcionales
    ├── README.md            # contrato común
    └── nixos/               # implementación incluida para NixOS-WSL
```

El core sólo coordina herramientas locales y proveedores:

```text
holodeck CLI
├── Git y archivos administrados localmente
├── SSH y GPG
├── GitHub mediante gh
└── GitLab mediante glab
```

Los backends de sistema no forman parte del flujo de identidades. Esto permite
usar o empaquetar el core de forma independiente y agregar instaladores para
otros sistemas sin introducir lógica específica en el comando `holodeck`.

## Requisitos

- Python 3.11 o posterior;
- Git y OpenSSH;
- `gh` para GitHub;
- `glab` para GitLab;
- GnuPG si se desea firmar commits o tags;
- un navegador para los inicios de sesión web de los proveedores.

El paquete Nix incluido en el repositorio padre aporta estas dependencias en
tiempo de ejecución. El paquete Python no agrega dependencias de terceros.

## Instalación

### Con Nix

Desde la raíz del repositorio que contiene este proyecto:

```bash
nix --extra-experimental-features "nix-command flakes" \
  run path:.#holodeck -- help
```

En una instalación administrada por este repositorio, Home Manager instala el
comando como parte del perfil de usuario:

```bash
./install.sh home-manager
```

### Desarrollo sin instalar

Desde la raíz del repositorio:

```bash
PYTHONPATH=holodeck/core python3 -m holodeck help
```

Desde este directorio también se puede usar:

```bash
PYTHONPATH=core python3 -m holodeck help
```

## Primer uso

Ejecutar como usuario normal, nunca con `sudo`:

```bash
holodeck setup
```

El asistente permite configurar el perfil personal de GitHub, el perfil
laboral de GitLab o ambos. Al terminar conviene verificar el resultado:

```bash
holodeck doctor
```

También se puede configurar cada proveedor por separado:

```bash
holodeck github
holodeck gitlab
```

## Comandos

| Comando | Función |
| --- | --- |
| `holodeck setup` | Ejecuta el asistente completo. |
| `holodeck github` | Configura el perfil personal de GitHub. |
| `holodeck gitlab` | Configura el perfil laboral de GitLab. |
| `holodeck login github` | Autentica solamente el cliente de GitHub. |
| `holodeck login gitlab` | Autentica solamente el cliente de GitLab. |
| `holodeck doctor` | Diagnostica perfiles, Git, SSH y autenticación. |
| `holodeck purge` | Retira el estado local administrado por Holodeck. |
| `holodeck help` | Muestra la ayuda disponible. |

`auth`, `profile`, `status`, `clean` y `sanitize` se conservan como aliases de
los comandos correspondientes.

## Archivos administrados

Holodeck no guarda estado personal dentro del repositorio. Respeta
`XDG_CONFIG_HOME` y, si no está definido, usa `~/.config`.

| Ruta | Contenido |
| --- | --- |
| `~/.config/holodeck/profiles/` | Metadatos locales de los perfiles. |
| `~/.config/holodeck/git/` | Configuraciones Git incluidas por directorio. |
| `~/.config/holodeck/public-keys/` | Copias de las claves públicas administradas. |
| `~/.ssh/holodeck_*` | Claves SSH independientes por perfil y proveedor. |
| `~/.gitconfig` | Un bloque delimitado de includes administrados. |
| `~/.ssh/config` | Un bloque delimitado de hosts administrados. |

Los bloques agregados a archivos existentes están delimitados explícitamente:

```text
# >>> holodeck git
# <<< holodeck git

# >>> holodeck ssh
# <<< holodeck ssh
```

Al retirarlos, Holodeck crea una copia con sufijo `.holodeck.bak` antes de
modificar el archivo correspondiente.

## Seguridad y límites

- El core rechaza su ejecución como `root`.
- Las credenciales siguen bajo el control de `gh`, `glab`, SSH y GPG.
- Sólo se activa un perfil después de validar su conexión SSH.
- Si GitHub bloquea el puerto 22, se puede usar `ssh.github.com` por el 443.
- El repositorio no recibe tokens, claves privadas ni sesiones de proveedor.
- `holodeck purge` exige una confirmación textual y no reescribe el historial
  de Git.

`purge` elimina configuración y autenticación local administrada, pero no
borra de GitHub o GitLab las claves públicas que ya se hayan publicado. Esas
claves se revocan desde cada proveedor.

## Defaults configurables

El wrapper Nix admite estos valores iniciales mediante variables de entorno:

| Variable | Default |
| --- | --- |
| `HOLODECK_DEFAULT_GITHUB_HOST` | `github.com` |
| `HOLODECK_DEFAULT_GITLAB_HOST` | `gitlab.com` |
| `HOLODECK_DEFAULT_PERSONAL_DIR` | `$HOME/projects/personal` |
| `HOLODECK_DEFAULT_WORK_DIR` | `$HOME/projects/work` |

Los asistentes muestran sus valores antes de escribir la configuración.

## Backends de sistema

Un backend externo implementa este contrato:

```text
holodeck-system-BACKEND install --repo RUTA [argumentos]
```

El único backend incluido actualmente es `holodeck-system-nixos` y acepta sólo
NixOS-WSL:

```bash
./install.sh nixos wsl

nix --extra-experimental-features "nix-command flakes" \
  run path:.#holodeck-system-nixos -- install --target wsl
```

Ese backend no inspecciona, particiona, formatea ni monta discos. Consultar el
[contrato de backends](backends/README.md) para agregar otra implementación.

## Integración opcional con Holodeck Control

El repositorio padre mantiene **Holodeck Control**, un frontend para Noctalia
que reúne el core con integraciones de AWS y una Windows VM declarativa. Esa
capa usa un IR versionado y un backend Nix; no mueve credenciales ni lógica de
sistema al frontend.

Estas piezas son adaptadores del ecosistema y no requisitos del core:

- [`holodeckctl`](../packages/holodeckctl/README.md), puente declarativo e IR;
- [plugin de Noctalia](../plugins/noctalia/holodeck-control/README.md), interfaz;
- [documentación de Holodeck Control](../docs/holodeck-control.md), arquitectura
  e integraciones.

## Pruebas

Desde este directorio:

```bash
PYTHONPATH=core \
  python3 -m unittest discover -s core/tests -v

PYTHONPATH=core:backends/nixos \
  python3 -m unittest discover -s backends/nixos/tests -v
```

La evaluación completa se ejecuta desde la raíz del repositorio:

```bash
nix --extra-experimental-features "nix-command flakes" \
  flake check path:. --print-build-logs
```

## Desarrollo

La CLI se mantiene deliberadamente pequeña y basada en la biblioteca estándar
de Python. Al modificar un flujo:

1. conservar separada la configuración local de la autenticación remota;
2. no imprimir tokens, claves privadas ni datos sensibles;
3. escribir únicamente dentro de bloques administrados;
4. validar el estado antes de activarlo;
5. cubrir los cambios con pruebas unitarias.

Las integraciones específicas de un sistema operativo deben agregarse como un
backend, no como una dependencia del core portable.
