# VSCodium

La feature vive en `modules/nixos/features/vscodium`.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.vscodium.enable` | bool | `false` | Instala VSCodium via `programs.vscode`. |
| `features.vscodium.defaultEditor` | bool | `false` | Configura VSCodium como editor por defecto. |

## Implementacion

Cuando esta activa:

```nix
programs.vscode = {
  enable = true;
  package = pkgs.vscodium;
  defaultEditor = cfg.defaultEditor;
  extensions = pkgs.vscode-utils.extensionsFromVscodeMarketplace (...);
};
```

Las extensiones se leen desde `modules/nixos/features/vscodium/extensions.json`.

## Extensiones actuales

- `catppuccin.catppuccin-vsc`
- `catppuccin.catppuccin-vsc-icons`
- `openai.chatgpt`

Cada extension queda pinneada por:

- `publisher`
- `name`
- `version`
- `sha256`
- opcionalmente `arch`

## Agregar o actualizar extensiones

Editar `modules/nixos/features/vscodium/extensions.json`:

```json
{
  "publisher": "example",
  "name": "extension-name",
  "version": "1.2.3",
  "sha256": "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA="
}
```

Despues correr una build. Si el hash no coincide, Nix va a mostrar el hash
esperado. Reemplazarlo en el JSON y volver a construir.

```bash
sudo nixos-rebuild build --flake .#desktop
```

## Activar como editor por defecto

Desde el host:

```nix
features.vscodium = {
  enable = true;
  defaultEditor = true;
};
```
