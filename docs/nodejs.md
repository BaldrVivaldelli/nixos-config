# Node.js

La feature vive en `modules/features/nodejs`.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.nodejs.enable` | bool | `false` | Instala tooling base de Node.js. |
| `features.nodejs.package` | package | `pkgs.nodejs` | Runtime Node.js a instalar. Incluye `npm` y `npx`. |
| `features.nodejs.pnpm.enable` | bool | `false` | Instala `pnpm` junto con Node.js. |
| `features.nodejs.yarn.enable` | bool | `false` | Instala `yarn` junto con Node.js. |

## Uso en desktop

El host `desktop` activa:

```nix
features.nodejs.enable = true;
```

Eso agrega al perfil del sistema:

- `node`
- `npm`
- `npx`

## Cambiar version o paquete de Node.js

Desde el host:

```nix
features.nodejs = {
  enable = true;
  package = pkgs.nodejs_22;
};
```

## Instalar pnpm o yarn

```nix
features.nodejs = {
  enable = true;
  pnpm.enable = true;
  yarn.enable = true;
};
```

## Crear un proyecto rapido

```bash
npm create vite@latest my-app
cd my-app
npm install
npm run dev
```

