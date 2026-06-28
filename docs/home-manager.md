# Home Manager

Home Manager esta integrado como modulo NixOS en `flake.nix`. Esto permite
declarar la configuracion del usuario `avivaldelli` junto con el sistema, pero
manteniendo responsabilidades separadas.

## Responsabilidades

NixOS/system:

- usuarios y shell por defecto
- servicios
- Docker/Podman
- paquetes base de sistema
- features como Python, Node.js, VSCodium, Holodeck y contenedores

Home Manager/user:

- `.zshrc` generado
- aliases
- funciones de shell
- prompt
- integraciones de fzf, zoxide y direnv
- helpers interactivos como `awslogin` y `awscxt`

## Estructura

```text
home/
  avivaldelli/
    default.nix
    shell.nix
    starship.nix
    aws.nix
```

`default.nix` define el usuario, `home.homeDirectory`, `home.stateVersion` e
imports.

`shell.nix` configura zsh:

- completion
- autosuggestions
- syntax highlighting
- history
- aliases basicos
- fzf
- zoxide
- direnv con nix-direnv

`starship.nix` configura el prompt.

`aws.nix` instala `awscli2` y define helpers de zsh.

## Aplicar cambios

Home Manager esta integrado al rebuild de NixOS, asi que no hace falta correr
`home-manager switch` separado:

```bash
sudo nixos-rebuild switch --flake .#desktop
```

Si agregaste archivos nuevos y todavia no estan trackeados por Git, validar con:

```bash
nix eval --offline path:$PWD#nixosConfigurations.desktop.config.system.build.toplevel.drvPath
```

## Zsh

El sistema habilita zsh y lo configura como shell de `avivaldelli`:

```nix
programs.zsh.enable = true;
users.users."avivaldelli".shell = pkgs.zsh;
```

Home Manager configura la experiencia interactiva.

Aliases incluidos:

```text
ll, la, ls
gs, gd, ga, gc
nixswitch, nixbuild, rebuild
```

## Starship

Starship se habilita desde Home Manager:

```nix
programs.starship.enable = true;
programs.starship.enableZshIntegration = true;
```

El prompt muestra modulos para Git, Nix, Node.js, Python y AWS.

## AWS helpers

`awslogin` corre AWS SSO:

```bash
awslogin
awslogin my-profile
```

`awscxt` selecciona un perfil con `fzf` y exporta variables en la shell actual:

```bash
awscxt
echo $AWS_PROFILE
```

Tambien queda disponible:

```bash
awsprofiles
awswho
```

`awscxt` es funcion de zsh porque necesita modificar el entorno de la shell
actual. Un binario externo no podria cambiar `AWS_PROFILE` del proceso padre.

