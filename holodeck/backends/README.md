# Holodeck system backends

Los backends de sistema son opcionales. El core portable no los importa.

El selector `install.sh` resuelve un ID `BACKEND` usando el nombre:

```text
holodeck-system-BACKEND
```

Primero busca un ejecutable en `PATH`. Si no existe y `nix` esta disponible,
intenta ejecutar la app `.#holodeck-system-BACKEND` de la flake.

## Contrato

Un backend debe aceptar:

```text
holodeck-system-BACKEND install --repo RUTA [argumentos]
```

Tambien debe:

- validar su plataforma antes de modificarla
- mantener sus dependencias fuera del core portable
- confirmar explicitamente cualquier accion destructiva
- no escribir identidad, llaves o credenciales del usuario
- dejar `holodeck setup` como onboarding posterior
- incluir pruebas propias

El backend de referencia vive en `nixos/` y expone los targets `desktop` y
`wsl`.
