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
- herramientas de desarrollo (incluidos Go, Rust y el toolchain C/C++),
  aplicaciones, Niri, Noctalia y Holodeck.

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

Kiro se instala junto con las aplicaciones de desarrollo en Linux x86-64. La
instancia de `nixpkgs` usada por Home Manager autoriza únicamente a Kiro como
paquete no libre; no habilita `allowUnfree` de forma global.

El perfil `minimal` conserva únicamente shell y Starship.

## Instalación centralizada

Para instalar Niri a nivel de sistema junto con este perfil, el flujo completo
es `./install.sh existing-nixos`. Para aplicar únicamente Home Manager:

```bash
./install.sh configure  # opcional; se ofrece automáticamente
./install.sh home-manager
```

`install.sh` ejecuta `verify-user-only.sh`, prepara un único snapshot, construye
`homeConfigurations.default.activationPackage` con un out-link persistente y
activa exactamente esa generación. Antes registra la generación actual en un
manifiesto privado. Si la activación falla, muestra el comando
`./install.sh recover MANIFEST` que restaura y reactiva la generación anterior.

Para aplicar ese mismo flujo y recargar Holodeck Control al final:

```bash
holodeck-regenerate
```

Su equivalente desde el checkout es `./install.sh regenerate`. No vuelve a
evaluar ni activa una segunda generación: `install.sh home-manager` ya activa
el candidato exacto. Sólo reinicia el plugin cuando Home Manager terminó
correctamente.

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
holodeck-regenerate
```

`rebuild` es alias de `hmswitch`.

## Integración WSL

`modules/home/default.nix` conecta el perfil a
la clave dinámica `home-manager.users.<username>` dentro de NixOS-WSL. El host
elige la identidad mediante `inventory.hosts.wsl.user` y desactiva las features
`developerTools`, `niri` y `noctalia` para no instalar aplicaciones gráficas;
las herramientas de terminal se declaran mediante sus features NixOS. Los
cambios del sistema WSL se aplican con el entrypoint seguro:

```bash
./install.sh nixos wsl
```

## AWS

Holodeck Control inicia AWS SSO y descubre cada cuenta y rol asignados.
`awslogin` renueva una sesión, `awscxt` selecciona y exporta un perfil,
`awsprofiles` lista perfiles y `awswho` muestra la identidad activa. Después
del login, cada cuenta/rol genera automáticamente perfiles `use1` y `use2`. El
editor permite asignar un alias personalizado o recomendado, conservar ambas
regiones, dejar sólo una o agregar otra como `sae1`; las elecciones se conservan
al resincronizar. Los nombres no secretos para completion se declaran con
`homeFeatures.aws.profiles`; las credenciales siguen fuera del repo.
