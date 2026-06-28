# Seguridad y secretos

Este repo no debe contener secretos. La configuracion declarativa puede referir
a herramientas y rutas, pero tokens, llaves privadas, credenciales y material
sensible deben vivir fuera del repo.

## Archivos ignorados

`.gitignore` bloquea:

- outputs de Nix como `result`
- caches locales
- `.env`
- `.ssh`
- `.gnupg`
- llaves privadas
- certificados
- archivos `.gpg`, `.pgp`, `.asc`, `.age`, `.kdbx`
- directorios `secrets`, `private`, `.secrets`, `.private`
- estado generado por Holodeck bajo `.config/holodeck`
- caches de Python y Node.js

## Hook pre-commit

Activar:

```bash
git config core.hooksPath .githooks
```

El hook analiza archivos stageados y bloquea:

- paths con nombres tipicos de secretos
- contenido que parece llave privada
- tokens tipo GitHub, GitLab, AWS o Slack

Si bloquea un commit, mover ese material a estado local fuera del repo.

## Holodeck

Holodeck esta pensado para mantener credenciales fuera de Git:

- perfiles en `~/.config/holodeck`
- llaves SSH en `~/.ssh/holodeck_*`
- llaves GPG en el keyring local
- auth de GitHub/GitLab manejada por `gh` y `glab`

`holodeck purge` elimina el estado local que Holodeck conoce, pero no borra
llaves publicas ya subidas a GitHub o GitLab.

## AWS

Home Manager instala `awscli2` y helpers de shell, pero no declara perfiles,
tokens ni credenciales. Esos datos deben seguir viviendo en estado local como
`~/.aws/config`, `~/.aws/credentials`, el navegador o el keyring usado por AWS
SSO.

## Windows VM

La password por defecto de la VM es declarativa:

```nix
features.containers.windowsVm.password = "admin";
```

Es comoda para una VM local, pero no debe tratarse como secreto real. Para usos
mas sensibles, cambiarla en la configuracion o por entorno local y evitar
commitear credenciales personales.

## Reglas practicas

- No commitear tokens, passwords ni llaves privadas.
- No guardar `.env` reales en el repo.
- No commitear exports privados de GPG.
- Usar un secret manager o archivos locales ignorados por Git.
- Si un secreto fue commiteado, rotarlo. Borrarlo del commit no alcanza si ya
  fue publicado.
