# Holodeck

Holodeck es una feature para preparar perfiles de desarrollo con Git, GitHub,
GitLab, SSH y GPG. Vive en `modules/features/holodeck`.

El comando esta implementado como un proyecto Python interno en
`modules/features/holodeck/app`. Nix solo lo envuelve para inyectar defaults y
asegurar que existan las herramientas externas.

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

- `default.nix`: opciones de la feature y paquetes base.
- `commands.nix`: wrapper Nix del comando `holodeck`.
- `app/pyproject.toml`: metadata del proyecto Python interno.
- `app/holodeck/`: paquete Python con la logica de Holodeck.

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
