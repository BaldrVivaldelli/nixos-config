# Browser

La feature vive en `modules/nixos/features/browser`.

Por ahora instala y configura Chromium de forma minimalista. No fuerza
extensiones ni policies opinadas; deja el punto preparado para personalizar el
navegador mas adelante.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.browser.enable` | bool | `false` | Instala y configura el browser. |
| `features.browser.package` | package | `pkgs.chromium` | Paquete de browser compatible con Chromium policies. |
| `features.browser.command` | string | `chromium-browser` | Ejecutable provisto por el paquete. |
| `features.browser.desktopFile` | string | `chromium-browser.desktop` | Desktop file para asociaciones xdg. |
| `features.browser.homepage` | null/string | `null` | Homepage opcional. |
| `features.browser.extensions` | list | `[ ]` | IDs de extensiones Chromium. |
| `features.browser.extraOpts` | attrs | `{ }` | Policies extra de Chromium. |
| `features.browser.search.enable` | bool | `true` | Configura buscador por defecto. |
| `features.browser.search.url` | string | Google | URL de busqueda. |
| `features.browser.search.suggestUrl` | string | Google | URL de sugerencias. |
| `features.browser.defaultBrowser.enable` | bool | `true` | Usa Chromium para links web y HTML. |

## Uso en desktop

El host `desktop` activa:

```nix
features.browser.enable = true;
```

Eso instala Chromium, agrega el comando `chromium`, habilita
`programs.chromium`, configura Google como buscador por defecto y usa Chromium
como aplicacion default para links web.

## Personalizar mas adelante

Ejemplo:

```nix
features.browser = {
  enable = true;
  homepage = "https://github.com/BaldrVivaldelli";

  extensions = [
    # Extension IDs de Chrome Web Store.
  ];

  extraOpts = {
    # Chromium enterprise policies.
  };
};
```
