# Holodeck: propuesta de UX

Referencia de diseño con [prototipo interactivo](holodeck-ux-prototype.html).
La navegación principal ya está implementada en el panel Luau de Noctalia; ver
[el funcionamiento nativo actual](holodeck-control.md). Los puntos sobre
progreso unificado y onboarding sin terminal siguen siendo objetivos del diseño.
El prototipo usa datos de ejemplo y simula las operaciones. No modifica cuentas,
archivos de configuración ni Windows.

## Objetivo y alcance

Resolver una tarea desde el panel abierto con un máximo de tres activaciones:
elegir la tarea, seleccionar una opción cuando haga falta y ejecutarla o
confirmarla. Abrir Holodeck no cuenta. Las operaciones que ya tienen todo
configurado terminan con la primera activación.

Esta métrica cuenta navegación, selección de acciones y confirmaciones. La
escritura, la edición de varios campos y la autenticación externa se registran
aparte. Un formulario de diez campos no se vuelve sencillo porque tenga un
solo botón: hay que medir también sus campos, elecciones, tiempo y errores.
Un límite literal de tres clics de mouse para editar arbitrariamente muchas
cuentas no es viable. El presupuesto se aplica a un recorrido normal hasta la
primera ejecución, con valores recordados y formularios mínimos. Los
reintentos, correcciones y vueltas atrás se registran, sin reiniciar el
contador para disimularlos.

El trabajo diario y la configuración del equipo tienen igual prioridad, como
pidió el usuario. La configuración inicial tiene pantallas propias que aparecen
sólo cuando faltan datos. El alcance incluye los pasos
interactivos que hoy se abren en terminal; lanzar un asistente no equivale a
completar la tarea.

## Problemas observados en el código actual

- Windows y AWS requieren abrir el panel, ir a Integraciones, elegir el
  proveedor y finalmente ejecutar la acción: cuatro activaciones.
- Cambiar la apariencia requiere abrir, ir a Sistema, cambiar el selector,
  guardar, generar plan y confirmar. Un selector desplegable añade interacción.
- La portada repite estados de configuración, sin ejecutar tareas cotidianas.
- AWS concatena todos los perfiles en una etiqueta y abre el editor de todas
  las asignaciones después de sincronizar.
- Windows reúne apertura, textos sobre credenciales, tamaño de ventana,
  diagnóstico y operaciones destructivas dentro de la misma tarjeta.
- `configured` significa cosas distintas según el proveedor. En AWS sólo
  indica que existen perfiles; no demuestra que la sesión esté vigente.
- Varias acciones sólo notifican que se abrió una terminal y requieren una
  recarga manual. El usuario no tiene un resultado claro en el panel.

Referencias: `plugins/noctalia/holodeck-control/panel.luau`, sus traducciones y
`packages/holodeckctl/src/holodeckctl/integrations.py`.

## Arquitectura propuesta

Sólo dos superficies: **inicio** y **tarea**. Sin Resumen, Sistema e
Integraciones como niveles sucesivos. Una tarea no lleva a otra subpantalla
antes de ejecutarse.

El inicio contiene:

1. Búsqueda de acciones, enfocada al abrir y con soporte de teclado.
2. Dos grupos con la misma jerarquía visual: **Trabajo** (AWS, Windows, GitHub
   y GitLab) y **Equipo** (apariencia, alcance de configuración, aplicar cambios
   y tamaño de Windows). Cada acción muestra una sola línea de contexto real.
3. Accesos directos a cambiar el perfil AWS y editar alias.
4. Todas las tareas restantes como filas compactas en la misma superficie,
   debajo de las principales. Desplazarse no abre otro nivel. La búsqueda
   filtra ese mismo catálogo: no es la única forma de encontrar una tarea.

El catálogo queda ordenado por frecuencia prevista, no reordenado en cada uso.
Los nombres expresan resultados: “Entrar a AWS”, “Abrir Windows”, “Aplicar
cambios”, “Cambiar contraseña”. Nunca “Guardar IR” o “Ejecutar backend”.

Una tarea muestra sólo los datos necesarios, un resultado esperado y una
acción principal. Las confirmaciones aparecen en esa misma pantalla. Volver
o cancelar no persiste un borrador ni dispara una operación.

## Recorridos

El panel ya está abierto al empezar a contar. Los recorridos con escritura o selección
de campos indican ese trabajo adicional; no se declara que termine en tres
clics físicos.

| Tarea | Clic 1 | Clic 2 | Clic 3 | Trabajo adicional |
| --- | --- | --- | --- | --- |
| Abrir Windows ya configurado | Abrir Windows | — | — | Esperar el inicio/RDP |
| Configurar Windows por primera vez | Abrir Windows | Crear y abrir | — | Usuario y contraseña, una sola vez |
| Entrar a AWS con el último perfil | Entrar a AWS | — | — | OAuth si hace falta |
| Configurar AWS por primera vez | Entrar a AWS | Conectar | Usar perfil descubierto | URL, región de SSO y OAuth |
| Cambiar perfil AWS | Cambiar perfil | Usar la fila elegida | — | Buscar si hace falta |
| Editar alias y regiones | Editar alias | Guardar cambios | — | Editar los campos necesarios |
| Descubrir cuentas AWS | Sincronizar cuentas | — | — | OAuth si hace falta |
| Conectar GitHub o GitLab | Conectar proveedor | Conectar, si faltan datos | — | Datos iniciales y OAuth |
| Cambiar apariencia | Apariencia | Claro u oscuro | Aplicar cambio | Build y privilegios si corresponden |
| Cambiar alcance de configuración | Alcance del equipo | Usuario o equipo completo | Aplicar cambio | Build y privilegios si corresponden |
| Aplicar configuración guardada | Aplicar cambios | Aplicar | — | Build y privilegios si corresponden |
| Cambiar tamaño de Windows | Tamaño de Windows | Media pantalla o Completa | — | — |
| Ver diagnóstico, estado o logs | La tarea correspondiente | — | — | Lectura del resultado |
| Detener Windows | Detener Windows | Detener | — | Confirmar la interrupción de la sesión |
| Reemplazar contraseña | Cambiar contraseña | Cambiar y reiniciar | — | Escribir la nueva contraseña |
| Recrear Windows | Borrar y reinstalar Windows | Borrar y reinstalar | — | Nueva credencial y escribir WIPE |

La búsqueda y las filas del catálogo llevan directamente a la misma tarea.
No hay un menú “Avanzado” que agregue un cuarto clic a las confirmaciones.

## Decisiones sobre funciones

**Conservar y simplificar:** login de proveedores, último perfil AWS, cambio de
perfil, alias/regiones, apertura y tamaño de Windows, aplicación del sistema.

**Separar:** renovar AWS no debe redescubrir cuentas ni abrir obligatoriamente
el editor. “Sincronizar cuentas” conserva esa función como tarea independiente.
El usuario elige cuándo necesita cambiar alias.

**Automatizar:** recordar elecciones, refrescar el estado al finalizar una
operación, validar cambios y preparar el resumen previo a aplicar. La UI no
expone guardar → planificar → aplicar como tres tareas distintas.

**Quitar de la portada:** rutas, hashes, versiones, conteos de integraciones,
listas completas de perfiles y explicaciones de implementación. Diagnóstico
puede mostrar detalles concretos cuando ayudan a resolver un problema.

**Retirar del flujo cotidiano:** “Configurar todo” y el desbloqueo manual
duplicado. El primero puede ser un onboarding guiado separado; el segundo
aparece como solución cuando falla la reparación automática, sin ocupar espacio
permanente. Sus comandos existentes pueden conservarse para soporte.

**Mantener con confirmación:** aplicar cambios, detener Windows, reemplazar
contraseñas y recrear la VM. La confirmación describe el efecto en el equipo;
recrear Windows conserva la exigencia de escribir WIPE.

**No agregar por ahora:** métricas decorativas, notificaciones de cada lectura,
una segunda navegación por categorías ni un gestor genérico de servicios.

## Cambios de comportamiento necesarios

El prototipo expresa comportamiento propuesto; estos contratos todavía no
existen completos en el backend:

- Compartir el último perfil de `~/.local/state/aws/last-profile` entre CLI y
  UI. El panel debe mostrar el seleccionado y no inventar un perfil activo.
  Elegirlo en la UI afecta los próximos comandos que consultan ese estado;
  no puede reescribir las variables de una terminal ya abierta.
- Distinguir sin configurar, configurado, sesión vencida, listo, ejecutando y
  error. Cuando no se puede verificar una sesión, mostrar “Sin verificar”.
- Renovar AWS con el último perfil sin abrir un selector en terminal. El
  selector aparece en la tarea sólo cuando no existe selección válida.
- Admitir datos iniciales validados desde las tareas GitHub/GitLab/Windows,
  para que la terminal no vuelva a hacer las mismas preguntas.
- Preparar y validar un borrador sin escribir el estado activo. Una única
  confirmación debe aplicar exactamente el borrador revisado, con detección
  de cambios concurrentes. Hoy `plan` sólo opera sobre el IR ya guardado.
- Informar progreso y finalización mediante un identificador de operación.
  Abrir una terminal o un proceso no permite afirmar “Listo”.
- Reutilizar las allowlists, locks y el transporte privado de credenciales
  existentes. Los textos introducidos no se interpolan en comandos.

## Validación antes de reemplazar la UI

- Auditar cada entrada del catálogo en estados configurado, inicial, ocupado
  y error; ninguna añade submenús a la ruta de ejecución.
- Medir por separado activaciones, campos y pasos de OAuth. Verificar el
  recorrido hasta el resultado, también fuera del panel.
- Probar por mouse y teclado, con el panel a 620 × 620, texto largo, muchas
  cuentas AWS y tema claro/oscuro. Mantener foco y scroll al actualizar estado.
- Evitar ejecuciones duplicadas; un error conserva el contexto y ofrece una
  acción concreta para reintentar.
- Verificar que cancelar no guarda configuración y que las acciones
  destructivas nunca se ejecutan desde un acceso rápido sin confirmación.

El prototipo es el material para acordar navegación, funciones y lenguaje.
La implementación posterior debe actualizar juntos el panel Luau, las
traducciones y los contratos del backend que esos recorridos necesiten.

## Comprobación del prototipo

Se recorrieron en Chromium las 18 tareas del catálogo y los cuatro primeros
usos de AWS, Windows, GitHub y GitLab. Todos terminaron dentro de tres
activaciones desde el panel abierto. También se verificaron búsqueda,
cancelación sin aplicar cambios, confirmación exacta WIPE, conservación del
formulario ante errores y conteo de reintentos. Se revisó el panel en claro y
oscuro, y el ancho reducido no genera desbordamiento horizontal.

Son comprobaciones de la navegación simulada. No validan autenticación real,
builds, recuperación de Windows ni el tiempo de ejecución del futuro backend.
