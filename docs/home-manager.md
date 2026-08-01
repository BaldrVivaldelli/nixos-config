# Home Manager

El perfil personal puede usarse de dos formas:

- standalone con `apply-home.sh`;
- integrado dentro del host `#wsl`.

## Perfil

`home/avivaldelli/default.nix` selecciona `developer`, que activa:

- shell Zsh, fzf, zoxide y direnv;
- Starship;
- AWS CLI y helpers;
- herramientas de desarrollo, aplicaciones y Holodeck.

El perfil `minimal` conserva únicamente shell y Starship.

## Instalación centralizada

```bash
./install.sh home-manager
```

`install.sh` ejecuta primero `verify-user-only.sh`, después
`apply-home.sh build` y finalmente `apply-home.sh switch`. Si un paso falla,
los siguientes no se ejecutan.

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
`home-manager.users.avivaldelli` dentro de NixOS-WSL. Ese host desactiva la
feature `developerTools` del usuario para no instalar aplicaciones gráficas;
las herramientas de terminal se declaran mediante sus features NixOS. Los
cambios del sistema WSL se aplican con:

```bash
sudo nixos-rebuild switch --flake .#wsl
```

## AWS

`awslogin` inicia AWS SSO, `awscxt` selecciona y exporta un perfil,
`awsprofiles` lista perfiles y `awswho` muestra la identidad activa. Los
nombres no secretos para completion se declaran con
`homeFeatures.aws.profiles`; las credenciales siguen fuera del repo.
