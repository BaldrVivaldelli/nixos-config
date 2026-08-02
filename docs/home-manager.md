# Home Manager

El perfil personal puede usarse de dos formas:

- standalone con `apply-home.sh`;
- integrado dentro del host `#wsl`.

## Perfil

El inventario efectivo elige un usuario lógico y su `homeProfile`. Si existe,
`inventory.local.nix` aporta la identidad detectada para esta máquina.
`home/default.nix` consume esa definición y, para el perfil `developer`, activa:

- shell Zsh, fzf, zoxide y direnv;
- Starship;
- AWS CLI y helpers;
- herramientas de desarrollo, aplicaciones, Niri, Noctalia y Holodeck.

Niri y Noctalia se administran juntos: Niri inicia la shell automáticamente y
Home Manager valida el archivo `~/.config/niri/config.kdl` durante el build.
La selección de Niri como sesión predeterminada es una responsabilidad NixOS y
se documenta en [niri.md](niri.md).

La feature de Noctalia instala además `holodeckctl`, el plugin Luau
`holodeck/control` y una entrada de launcher `Holodeck Control`. Todo queda
incluido en los flujos existentes de `./install.sh`; no hay un instalador
paralelo para el plugin.

El perfil publica Zsh en `SHELL` y redirige a Zsh las terminales interactivas
que todavía arranquen Bash. Esto permite usarlo también en instalaciones donde
Home Manager no puede cambiar el login shell de `/etc/passwd`. Para abrir Bash
de forma explícita se puede ejecutar `HM_KEEP_BASH=1 bash`; scripts y
`bash -c` no se redirigen.

Chromium se instala en el perfil y queda como navegador predeterminado para
links web, documentos HTML/XML y PDF mediante asociaciones XDG.

El perfil `minimal` conserva únicamente shell y Starship.

## Instalación centralizada

Para instalar Niri a nivel de sistema junto con este perfil, el flujo completo
es `./install.sh existing-nixos`. Para aplicar únicamente Home Manager:

```bash
./install.sh configure  # opcional; se ofrece automáticamente
./install.sh home-manager
```

`install.sh` ejecuta primero `verify-user-only.sh`, después
`apply-home.sh build` y finalmente `apply-home.sh switch`. Si un paso falla,
los siguientes no se ejecutan.

`apply-home.sh` siempre usa `homeConfigurations.default`; el nombre real, el
home y la ruta del repositorio se derivan del inventario. La flake conserva
además aliases generados por username para uso manual.

Durante el primer `switch`, cualquier archivo manual que entre en conflicto
con uno administrado por Home Manager se conserva junto al original con
extensión `.hm-bak`. Esto permite migrar, por ejemplo, el `settings.json`
existente de VSCodium sin perderlo.

El flujo se ejecuta sin `sudo` y habilita `nix-command` y `flakes` sólo
para sus procesos. Los scripts individuales siguen disponibles para construir
o activar por separado durante el desarrollo.

Aliases disponibles:

```text
hmbuild
hmswitch
hmverify
rebuild
```

`rebuild` es alias de `hmswitch`.

## Integración WSL

`modules/home/default.nix` conecta el perfil a
la clave dinámica `home-manager.users.<username>` dentro de NixOS-WSL. El host
elige la identidad mediante `inventory.hosts.wsl.user` y desactiva las features
`developerTools`, `niri` y `noctalia` para no instalar aplicaciones gráficas;
las herramientas de terminal se declaran mediante sus features NixOS. Los
cambios del sistema WSL se aplican con:

```bash
sudo nixos-rebuild switch --flake path:.#wsl
```

## AWS

`awslogin` inicia AWS SSO, `awscxt` selecciona y exporta un perfil,
`awsprofiles` lista perfiles y `awswho` muestra la identidad activa. Los
nombres no secretos para completion se declaran con
`homeFeatures.aws.profiles`; las credenciales siguen fuera del repo.
