# Holodeck

Holodeck prepara perfiles de desarrollo con Git, GitHub, GitLab, SSH y GPG. Su
core es portable y vive en `holodeck/core`; no importa codigo NixOS ni incluye
`nix`, `sudo`, Disko, `util-linux` o `xdg-open` en su runtime.

La integracion NixOS que instala el comando sigue en
`modules/nixos/features/holodeck`. Nix solo empaqueta el core, inyecta defaults y
asegura que existan las herramientas externas.

Cuando esta activa, instala herramientas de desarrollo y publica el comando
`holodeck`:

- `git`
- `gh`
- `glab`
- `gnupg`
- `openssh`
- comando `holodeck`
- agente de GnuPG

El wrapper del comando incluye `python3` como runtime interno. Para tener
`python3` disponible como comando global del sistema, usar `features.python`.

## Implementacion

Archivos principales:

- `holodeck/core/pyproject.toml`: metadata del core portable.
- `holodeck/core/holodeck/`: identidad, providers y estado de usuario.
- `holodeck/core/tests/`: pruebas que no requieren NixOS.
- `modules/nixos/features/holodeck/default.nix`: opciones de la feature NixOS.
- `modules/nixos/features/holodeck/package.nix`: wrapper Nix del core.
- `modules/nixos/features/holodeck/commands.nix`: integra el paquete al sistema.
- `holodeck/backends/nixos/`: backend opcional de instalacion NixOS/Disko.

`commands.nix` exporta estos defaults antes de ejecutar Python:

```text
HOLODECK_DEFAULT_GITHUB_HOST
HOLODECK_DEFAULT_GITLAB_HOST
HOLODECK_DEFAULT_PERSONAL_DIR
HOLODECK_DEFAULT_WORK_DIR
```

Los colores usan ANSI cuando stdout es una terminal. Para desactivarlos:

```bash
NO_COLOR=1 holodeck doctor
```

El wrapper ejecuta el paquete con:

```bash
python3 -m holodeck
```

La flake tambien publica:

```bash
nix run .#holodeck -- --help
```

Esto ejecuta solamente el core portable.

## Opciones

| Opcion | Default | Descripcion |
| --- | --- | --- |
| `features.holodeck.enable` | `false` | Activa la feature. |
| `features.holodeck.githubHost` | `github.com` | Host GitHub por defecto. |
| `features.holodeck.gitlabHost` | `gitlab.com` | Host GitLab por defecto. |
| `features.holodeck.personalProjectsDir` | `$HOME/projects/personal` | Directorio de proyectos personales. |
| `features.holodeck.workProjectsDir` | `$HOME/projects/work` | Directorio de proyectos laborales. |

## Primer uso

```bash
holodeck setup
```

El wizard permite configurar:

- perfil personal de GitHub
- perfil laboral de GitLab
- autenticacion con `gh` y `glab`
- llaves SSH por perfil
- llave GPG de firma por email
- bloques manejados en `~/.gitconfig` y `~/.ssh/config`

## Comandos

```text
holodeck setup
holodeck github
holodeck gitlab
holodeck login github
holodeck login gitlab
holodeck auth github
holodeck auth gitlab
holodeck profile github
holodeck profile gitlab
holodeck doctor
holodeck status
holodeck purge
holodeck clean
holodeck sanitize
```

Aliases:

- `auth` y `login` hacen lo mismo.
- `profile github` equivale a `github`.
- `profile gitlab` equivale a `gitlab`.
- `status` equivale a `doctor`.
- `clean` y `sanitize` equivalen a `purge`.

## Instalacion de sistema

La instalacion no forma parte del core. Desktop tiene un entrypoint directo:

```bash
./install-desktop.sh
```

NixOS esta implementado como el ejecutable opcional
`holodeck-system-nixos`:

```bash
./install.sh nixos wsl
```

El selector llama la app de la flake:

```bash
nix run .#holodeck-system-nixos -- install --target desktop
nix run .#holodeck-system-nixos -- install --target wsl
```

El backend:

- valida que el checkout contenga la flake y el target solicitado
- rechaza inputs de instalacion sin seguimiento en Git
- ejecuta `nix flake check` antes de modificar el sistema
- para desktop exige UEFI, detecta discos completos mediante `/dev/disk/by-id`,
  excluye el disco del sistema activo, prefiere los internos y pide elegir si
  hay varios
- permite seleccionar el disco raiz solamente combinando `--disk` con
  `--allow-running-system-disk`; exige dos confirmaciones y salta con `kexec` a
  un instalador en RAM antes de tocarlo
- despues de la confirmacion desactiva swap, desmonta el destino y revalida que
  quedo libre antes de llamar Disko
- verifica que Disko haya montado `/mnt` y una ESP `vfat` en `/mnt/boot`
- al terminar sincroniza y desmonta `/mnt` automaticamente
- para WSL verifica que la sesion sea realmente WSL y prepara `#wsl` con
  `nixos-rebuild boot`

El layout sigue definido en `modules/hosts/desktop/disko.nix` y la
configuracion de plataforma permanece bajo `modules/hosts`. El backend instala
`#desktop-disko`; `#desktop` queda reservado para el layout del sistema fisico
anterior y no importa Disko.

`--disk /dev/disk/by-id/ID` queda como override avanzado y no es necesario para
la instalacion normal. Por si solo no autoriza el disco raiz; esa excepcion
requiere tambien `--allow-running-system-disk`.

## Agregar otro sistema

`install.sh` usa el mismo nombre para apps de flake y ejecutables:

```text
holodeck-system-<backend> install --repo <ruta> [argumentos]
```

Por ejemplo:

```bash
./install.sh ubuntu
```

primero busca `holodeck-system-ubuntu` en `PATH` y, si existe `nix`, intenta la
app `.#holodeck-system-ubuntu`. Ese backend puede usar apt, cloud-init o
cualquier mecanismo propio sin agregar dependencias al core de Holodeck.

Todo backend debe:

- aceptar `install --repo <ruta>`
- manejar sus propios argumentos y selección de targets
- contener sus dependencias privilegiadas fuera del core
- no generar credenciales ni identidad del usuario durante la instalacion
- indicar `holodeck setup` como paso posterior cuando corresponda

La instalacion privilegiada no genera SSH/GPG ni autentica providers. Despues
del reinicio se ejecuta como usuario normal:

```bash
holodeck setup
```

Los comandos que escriben identidad o credenciales rechazan su ejecucion como
`root`, para no crear estado accidental en `/root`.

## Estado que maneja

Holodeck guarda estado local en:

```text
~/.config/holodeck/
  profiles/
  git/
  public-keys/
~/.ssh/holodeck_*
~/.gitconfig
~/.ssh/config
```

En `~/.gitconfig` escribe un bloque manejado:

```text
# >>> holodeck git
...
# <<< holodeck git
```

En `~/.ssh/config` escribe otro bloque:

```text
# >>> holodeck ssh
...
# <<< holodeck ssh
```

Cuando reescribe esos archivos, crea backup con sufijo `.holodeck.bak`.

## Como enruta identidades Git

Cada perfil tiene un directorio de proyectos. Holodeck genera un archivo
`.gitconfig` por perfil y luego usa `includeIf "gitdir:<dir>/**"`.

Ejemplo conceptual:

```gitconfig
[includeIf "gitdir:/home/user/projects/personal/**"]
  path = /home/user/.config/holodeck/git/user.gitconfig
```

Los repos dentro de ese directorio heredan el nombre, email y signing key del
perfil. Los repos fuera de esos directorios no reciben esa identidad de
Holodeck.

## GitHub

`holodeck github`:

1. autentica con `gh auth login`
2. lee datos de la cuenta con `gh api`
3. elige nombre, email primario verificado o email noreply
4. crea perfil local
5. genera o reutiliza llaves SSH/GPG
6. intenta subir llaves publicas a GitHub

Si GitHub requiere scope adicional para subir la llave GPG, Holodeck intenta:

```bash
gh auth refresh --hostname github.com --scopes write:gpg_key
```

## GitLab

`holodeck gitlab` pide host, directorio de proyectos, nombre y email. Luego
puede autenticar con `glab`, generar llaves y subir la llave SSH. Para GPG,
si `glab` no expone el comando necesario, abre la pagina de configuracion de
GitLab y muestra donde esta la llave publica exportada.

## Doctor

```bash
holodeck doctor
```

Muestra:

- directorio de Holodeck
- perfiles configurados
- provider y host por perfil
- directorio de proyectos
- email
- llave SSH
- fingerprint GPG
- estado de auth de GitHub y GitLab

## Purge

```bash
holodeck purge
```

Pide escribir `purge holodeck` y luego elimina estado local manejado:

- bloques de `~/.gitconfig` y `~/.ssh/config`
- `~/.config/holodeck`
- `~/.ssh/holodeck_*`
- llaves GPG locales rastreadas por Holodeck
- auth local de `gh` y `glab` para hosts de perfiles

No reescribe historia Git y no borra llaves publicas ya subidas a GitHub o
GitLab.
