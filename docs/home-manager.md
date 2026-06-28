# Home Manager

Home Manager esta integrado como modulo NixOS desde `modules/parts.nix`. Esto
permite declarar la configuracion del usuario `avivaldelli` junto con el
sistema, pero manteniendo responsabilidades separadas.

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
modules/
  home/
    default.nix
    features/
      shell/
        default.nix
        completions.nix
      starship/
        default.nix
      aws/
        default.nix
    profiles/
      developer/
        default.nix
      minimal/
        default.nix
```

`modules/home/default.nix` es un modulo NixOS que configura Home Manager:
`useGlobalPkgs`, `useUserPackages`, backups y el usuario `avivaldelli`.

`home/avivaldelli/default.nix` define el usuario, `home.homeDirectory`,
`home.stateVersion` e importa un perfil Home Manager.

Los perfiles viven en `modules/home/profiles`:

- `developer`: shell, starship y AWS. Es el perfil default de `avivaldelli`.
- `minimal`: shell y starship, sin helpers cloud.

Cada perfil referencia modulos Home Manager reutilizables desde
`modules/home/features`.

## Cambiar perfil

El perfil activo se elige desde `home/avivaldelli/default.nix`:

```nix
imports = [
  ../../modules/home/profiles/developer
];
```

Para probar un perfil mas chico:

```nix
imports = [
  ../../modules/home/profiles/minimal
];
```

`modules/home/features/shell/default.nix` configura zsh:

- completion
- autosuggestions
- syntax highlighting
- history
- aliases basicos
- fzf
- zoxide
- direnv con nix-direnv

`modules/home/features/shell/completions.nix` declara datos de completion para
`windowsvm`, `holodeck`, `awslogin` y `awscxt`, y genera las funciones zsh desde
helpers Nix.

`modules/home/features/starship/default.nix` configura el prompt.

`modules/home/features/aws/default.nix` instala `awscli2` y define helpers de
zsh.

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

Completions custom incluidas:

```text
windowsvm up|start|rdp|web|status|logs|down|rm
holodeck setup|github|gitlab|login|doctor|purge
awslogin <declarative-profile>
awscxt <declarative-profile>
```

Los perfiles AWS no se leen dinamicamente desde `~/.aws/config`; si queres
completion de perfiles, agregalos como nombres no secretos en
`modules/home/features/shell/completions.nix`.

Si acabas de aplicar cambios y una completion no aparece, abrir una nueva shell
deberia alcanzar. Si zsh conserva cache vieja:

```bash
rm -f ~/.zcompdump*
exec zsh
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
