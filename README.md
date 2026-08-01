# Configuración de usuario con Home Manager

Este repositorio administra aplicaciones y configuración del usuario
`avivaldelli`. No contiene una configuración de host NixOS y no puede tocar
particiones, UUID, LUKS, bootloader, kernel ni filesystems.

## Aplicar la configuración

`apply-home.sh` habilita `nix-command` y `flakes` únicamente durante su ejecución. No modifica `/etc/nix/nix.conf`.


`build` solamente comprueba que todo pueda construirse:

```bash
./apply-home.sh build
```

Para instalar y activar los programas del usuario hay que ejecutar:

```bash
./apply-home.sh switch
```

Luego de la primera activación quedan disponibles:

```bash
hmbuild   # construir sin activar
hmswitch  # construir y activar
hmverify  # comprobar que no haya configuración de sistema
```

## Programas administrados

La activación instala en el perfil del usuario:

- Chromium y VSCodium.
- Git, Git LFS, Delta, Lazygit, GitHub CLI y GitLab CLI.
- Python, uv, Node.js y elan.
- AWS CLI.
- Holodeck.
- wget, curl, OpenSSH, GnuPG, FreeRDP y utilidades XDG.
- Zsh, Starship, fzf, zoxide, direnv, eza, fd, jq y ripgrep.

Los programas se instalan en el perfil de Home Manager y no en el perfil global
de NixOS.

## Qué no puede administrar Home Manager

Servicios y componentes como GNOME/GDM, PipeWire, controladores gráficos,
Docker daemon, usuarios/grupos, red y bootloader son configuración de sistema.
Esta variante no los modifica ni intenta instalarlos.

## Reemplazo seguro del repositorio anterior

No descomprimir encima del repositorio viejo:

```bash
mv ~/projects/personal/nixos-config \
  ~/projects/personal/nixos-config-system-backup

mv nixos-config-user-programs-fixed \
  ~/projects/personal/nixos-config

cd ~/projects/personal/nixos-config
./verify-user-only.sh
./apply-home.sh build
./apply-home.sh switch
```

Todos los comandos deben ejecutarse como usuario normal, sin `sudo`.

## Inicio de sesión de GitHub sin logs de Chromium

Holodeck establece `GH_BROWSER` únicamente dentro de su propio proceso y abre
la URL mediante un launcher desacoplado. La ventana del navegador se sigue
abriendo normalmente, pero su salida estándar y sus diagnósticos internos no
se imprimen en la terminal.

Para aplicar esta corrección:

```bash
./apply-home.sh build
./apply-home.sh switch
```

Después se puede ejecutar nuevamente:

```bash
holodeck github
```

## Holodeck: GitHub y Git verificados

La versión 0.4.0 corrige el flujo en el que `gh` podía autenticar una llave y
Holodeck configurar otra distinta.

Ahora `holodeck github`:

1. autentica GitHub sin permitir que `gh` seleccione o suba otra llave SSH;
2. genera o reutiliza `~/.ssh/holodeck_<perfil>_github`;
3. registra exactamente esa llave pública en GitHub;
4. prueba la autenticación SSH real;
5. si el puerto 22 está bloqueado, prueba automáticamente `ssh.github.com:443`;
6. activa la configuración Git solamente después de verificar la conexión;
7. comprueba que `includeIf` cargue el nombre y correo dentro de
   `~/projects/personal`.

La firma GPG queda desactivada en el flujo automático de GitHub. Git y SSH no
dependen de `gpg-agent` ni de `pinentry`.

Para reparar una instalación creada con una versión anterior:

```bash
./apply-home.sh switch
holodeck github
holodeck doctor
```

No hace falta ejecutar `holodeck purge`: el comando reutiliza la llave
`holodeck_*` existente y reescribe únicamente los bloques administrados por
Holodeck.
