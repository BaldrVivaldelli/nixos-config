# Holodeck system backends

Los backends de sistema permanecen separados del core portable de Holodeck y
siguen el contrato:

```text
holodeck-system-BACKEND install --repo RUTA [argumentos]
```

`install.sh` busca primero un ejecutable con ese nombre y luego una app de la
flake. Esto permite conservar integraciones futuras sin agregar dependencias de
sistema al comando `holodeck`.

El backend incluido vive en `nixos/` y expone sólo el target `wsl`:

```bash
./install.sh nixos wsl
nix run path:.#holodeck-system-nixos -- install --target wsl
```

La instalación del desktop físico y toda lógica de discos fueron retiradas.
