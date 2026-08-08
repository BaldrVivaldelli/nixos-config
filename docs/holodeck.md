# Holodeck

El README principal del proyecto portable está en
[`holodeck/README.md`](../holodeck/README.md). Este documento resume cómo se
integra con la flake, Home Manager y los backends de este repositorio.

Holodeck conserva dos responsabilidades separadas:

- el core portable configura Git/GitHub y autentica GitLab;
- los backends opcionales instalan sistemas declarados.

El plugin **Holodeck Control** reúne esas capacidades con AWS y la Windows VM
en una interfaz Noctalia. Conserva la lógica y las credenciales en sus comandos
originales; el frontend sólo muestra estado no sensible y abre flujos
allowlisted. Los flujos interactivos conservan una terminal visible, mientras
que RDP y Web se lanzan directamente. Ver
[holodeck-control.md](holodeck-control.md).

## Core

El core vive en `holodeck/core` y el wrapper Nix en
`packages/holodeck/default.nix`. El perfil Home Manager instala el comando
`holodeck` junto con `git`, `gh`, `glab`, `gnupg` y `openssh`.

Comandos principales:

```text
holodeck setup
holodeck github
holodeck gitlab
holodeck login github|gitlab
holodeck doctor
holodeck purge
```

El estado local vive en `~/.config/holodeck`, `~/.ssh`, `~/.gitconfig` y
`~/.ssh/config`, nunca dentro del repositorio.

El flujo `holodeck gitlab` acepta la URL de la instancia o de un grupo, como
`https://gitlab.com/nave-negocios`. Extrae el host para reutilizar o abrir el
login web OAuth/SSO de `glab` y termina allí: no crea perfiles, claves SSH ni
routing Git. Ningún host GitLab queda fijado en Nix ni en el código.

## Backend NixOS

El backend `holodeck-system-nixos` se conserva para NixOS-WSL:

```bash
./install.sh nixos wsl
```

Ya no ofrece un target `desktop`, opciones de disco ni dependencias de
`util-linux` o Disko.

## Backends externos

`install.sh ubuntu`, por ejemplo, busca primero
`holodeck-system-ubuntu` en `PATH` y luego la app
la app `holodeck-system-ubuntu` dentro del snapshot seguro. Así se mantiene el mecanismo extensible sin
mezclarlo con el core portable.

## Pruebas

```bash
PYTHONPATH=holodeck/core \
  python3 -m unittest discover -s holodeck/core/tests -v

PYTHONPATH=holodeck/core:holodeck/backends/nixos \
  python3 -m unittest discover -s holodeck/backends/nixos/tests -v
```
