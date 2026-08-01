# Inventario de usuarios y hosts

El inventario tiene dos capas:

- `inventory.nix` guarda defaults portables y versionados;
- `inventory.local.nix` guarda los datos detectados de una máquina y Git lo
  ignora.

Los módulos reutilizables no contienen nombres de usuario ni rutas personales.
La capa local se combina recursivamente sobre los defaults, por lo que sólo
necesita declarar los valores específicos del equipo.

## Autocompletar desde el sistema

```bash
./install.sh configure
```

El proceso detecta y muestra:

- sistema operativo, arquitectura y plataforma Nix;
- usuario, home y ubicación absoluta/relativa del repositorio;
- hostname y zona horaria;
- si la sesión está dentro de WSL.

Después pide confirmación y escribe el archivo de forma atómica. No inspecciona
discos, particiones, UUID, filesystems ni montajes. `--print` permite revisar el
resultado sin escribir, `--yes` sirve para automatización y un archivo existente
sólo se reemplaza explícitamente con `--force`.

`install.sh home-manager` y `install.sh nixos wsl` ofrecen este preflight
automáticamente cuando falta el archivo y hay una terminal. Sin TTY mantienen
los defaults, de modo que CI no queda esperando input.

Como el archivo local está ignorado por Git, las evaluaciones manuales que deban
verlo deben usar una flake de tipo path:

```bash
nix flake check path:.
sudo nixos-rebuild switch --flake path:.#wsl
```

La configuración efectiva usa una clave lógica llamada `personal`:

```nix
{
  defaultHomeUser = "personal";

  users.personal = {
    username = "usuario-del-sistema";
    homeProfile = "developer";
    repoRelativePath = "projects/personal/nixos-config";
  };

  machine = {
    hostName = "mi-equipo";
    timeZone = "America/Argentina/Buenos_Aires";
  };

  hosts.wsl = {
    user = "personal";
  };
}
```

La clave lógica puede mantenerse aunque cambie el nombre real. A partir de
`username` se deriva `homeDirectory` como `/home/<username>`; puede declararse
explícitamente si una máquina usa otra ubicación. `repoPath` se deriva de ese
home y `repoRelativePath`. El generador también declara `repoPath` de manera
explícita para soportar repositorios ubicados fuera del home.

## Agregar otro usuario

Agregar una entrada sin crear carpetas ni módulos específicos:

```nix
users.laptop = {
  username = "otro-usuario";
  homeProfile = "developer";
};
```

Para convertirlo en el perfil usado por `apply-home.sh`:

```nix
defaultHomeUser = "laptop";
```

Para asignarlo a WSL:

```nix
hosts.wsl.user = "laptop";
```

La flake publica `homeConfigurations.default` para los scripts y genera además
un alias por cada `username`. El alias `default` evita que los instaladores
necesiten conocer la identidad activa.

## Perfiles

`homeProfile` elige una composición bajo `modules/home/profiles`:

- `developer`: entorno personal completo;
- `minimal`: shell y Starship.

Agregar una nueva composición requiere registrarla una sola vez en
`home/default.nix`; los usuarios sólo guardan el nombre del perfil.
