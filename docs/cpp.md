# C y C++

La feature `features.cpp` instala un entorno de desarrollo C/C++ completo en
hosts NixOS.

## Toolchain predeterminado

- GCC, que proporciona `gcc` y `g++`.
- binutils, con el linker y utilidades como `ld`, `ar` y `nm`.
- GNU Make, CMake y Ninja.
- pkg-config para descubrir dependencias del sistema.
- GDB para depuracion.
- clang-tools para `clangd`, `clang-format` y analisis estatico.

## Opciones

| Opcion | Tipo | Default | Descripcion |
| --- | --- | --- | --- |
| `features.cpp.enable` | bool | `false` | Instala el entorno C/C++. |
| `features.cpp.compiler` | package | `pkgs.gcc` | Compilador C/C++ a instalar. |
| `features.cpp.buildTools` | list of package | binutils, Make, CMake, Ninja y pkg-config | Herramientas de build y enlazado. |
| `features.cpp.debugger.enable` | bool | `true` | Instala GDB. |
| `features.cpp.clangTools.enable` | bool | `true` | Instala clangd, clang-format y herramientas relacionadas. |

## Uso

```nix
features.cpp.enable = true;
```

El perfil Home Manager `developer` instala el mismo conjunto directamente. El
host NixOS-WSL habilita esta feature para mantener disponible el toolchain sin
instalar las aplicaciones graficas del perfil.

## Personalizacion

```nix
features.cpp = {
  enable = true;
  compiler = pkgs.gcc;
  buildTools = with pkgs; [
    gnumake
    cmake
  ];
  debugger.enable = false;
  clangTools.enable = false;
};
```

## Verificacion

```bash
gcc --version
g++ --version
cmake --version
gdb --version
clangd --version
```
