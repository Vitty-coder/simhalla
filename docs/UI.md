# UI — Aplicación, interfaz y almacenamiento (fase 9)

Arquitectura en tres capas (PROJECT.md §17.2: «la aplicación coordina y la UI consume resultados»; «la UI no ejecuta reglas de combate propias»):

| Capa | Código | Responsabilidad |
|---|---|---|
| **Almacenamiento** | `src/storage` (`AppStorage`, `VersionedStore`, `RecordStore`, `BundleIO`) | Persistencia, índices, versiones inmutables, huellas, exportación portable |
| **Aplicación** | `src/application` (`AppController` + modelos) | Casos de uso sin nodos: biblioteca, importación, configuración de duelo, visor, lotes, informes, reglas/equilibrio, ajustes. Totalmente probable en headless |
| **Interfaz** | `src/ui` (`MainUI`, pantallas, widgets, `LocaleService`) | Escenas Godot 2D que **solo presentan** lo que devuelven los modelos y delegan las acciones |

## 1. Almacenamiento (`AppStorage`, bajo `user://simhalla`; offline; PC y Android)
| Sección | Almacén | Contenido |
|---|---|---|
| `library/` | `ContentLibrary` | paquetes versionados (personajes, habilidades, IA); `remove` |
| `rulesets/`, `profiles/`, `configs/` | `VersionedStore` | reglamentos, perfiles de equilibrio y configuraciones (`duel`/`batch`) **versionados e inmutables** (`id@version`, huella SHA-256) |
| `battles/`, `batches/`, `reports/` | `RecordStore` | registros con id secuencial (`b0001`, `l0001`, `r0001`, sin reloj), índice local `index.json`, huella de archivos, `refs` y metadatos (`saved_at` es solo informativo) |
| `settings.json` | `AppStorage.settings()` | idioma, modo por defecto, presupuesto, perfil, hilos, historial |
- **Colisiones explícitas:** mismo `id@version` con contenido distinto ⇒ `[colision]` / `[version_conflicto]`; se rechaza o se guarda como **versión nueva** (`put_resolving`, importación «como versión nueva»). Nunca se sobrescribe lo necesario para reproducir.
- **Combates guardados reproducibles:** `pin_config` fija paquetes a **versión exacta + huella**, entidades sueltas como datos inline y reglamento/perfil como **instantáneas inline** (`ruleset_data`, `profile_data`); `replay_battle` re-ejecuta y comprueba el `log_hash` (aviso si cambió el motor; error `[contenido_alterado]` si el contenido fijado cambió).
- **Borrado protegido:** `remove_package` / `remove_record` se rechazan mientras otro registro los referencie (`[referenciado]`).
- **Integridad:** cada lectura recalcula la huella (`[integridad]`).
- **Exportación portable** (`BundleIO`, `.simbundle` = ZIP): registros + los **paquetes exactos** que referencian. Importación segura: lectura con las defensas de `PackageSource` (rutas, tamaños, bombas), huella de cada archivo, paquetes validados por `PackageImporter` y con la huella esperada, ids nuevos con referencias remapeadas, conflicto de versión = error sin importar nada. No se ejecuta nada del bundle. Límite: 256 archivos y 16 MB por bundle (los de `PackageSource`).

- **Historial de la biblioteca** (`history.json`, `AppStorage.history/log_event`): importaciones, ejemplos instalados, borrados, bundles importados y exportaciones, con contador `seq` (sin reloj; `saved_at` solo informativo), tope de 500 y tolerancia a archivo ilegible. La biblioteca muestra las últimas 10 operaciones.
- **Exportar la biblioteca** (`BundleIO.export_library`, botón «Exportar biblioteca»): bundle `.simbundle` solo con paquetes (todos o una selección `id@version`), verificando integridad antes. La importación de bundles reintenta los paquetes hasta resolver dependencias entre ellos, y **toda exportación incluye las dependencias transitivas** de sus paquetes (si falta alguna: `[dependencia]`), de modo que un bundle se importa en una instalación limpia.

## 2. Modelos de aplicación (`AppController` + `src/application`)
- `AppController`: navegación (`go`/`back`, historial), ajustes, perfil/reglamento activos, `cost_report`, señales `screen_changed`/`settings_changed`.
- `LibraryModel`: búsqueda y filtro por tipo, versiones, detalle (stats, habilidades, IA, scripts, dependencias, **integridad**, **coste frente a presupuesto**, registros que lo usan).
- `ImportModel`: **vista previa sin almacenar** (errores por archivo y ruta, avisos, coste/presupuesto según modo), detección de colisión y política `reject`/`new_version`.
- `DuelSetupModel`: contendientes (paquete + restricción de versión, IA alternativa, `patch`), reglamento, perfil, **modo libre/reglamentado**, presupuesto, semilla, estado inicial. `validate()` muestra **antes del combate** versión y huella exactas, coste, presupuesto, advertencias y errores; en reglamentado los incumplimientos bloquean (`can_start`).
- `ViewerModel`: pausa/reanudar, velocidad (pasos por tick), avanzar por acción/turno, `seek` (**retroceder reconstruyendo**), repetir con la misma semilla, registro legible (`EventText`, localizado), **inspección de evento** (cadena causal, fórmulas, tiradas), guardar combate e informe, reproducir un combate guardado.
- `BatchModel`: planes de las 7 modalidades con versiones fijadas, ejecución (cooperativa o hilos), progreso, cancelación, guardado e informe.
- `ReportsModel`: lista/búsqueda, abrir en MD/JSON/HTML, documento nativo, verificar, exportar, borrado protegido, generar desde combates/lotes guardados.
- `RulesModel`: reglamentos y perfiles (con aviso de perfil **ILUSTRATIVO**), perfil activo, importar con colisión explícita, valorar un personaje.

## 3. Interfaz (`src/ui`)
- **Pantallas** (§16): Biblioteca, Importación/validación y detalle de PJ, Configuración de duelo, Visor de batalla, Lotes (configuración y ejecución), Informes, Reglas y equilibrio, Depuración, Ajustes.
- **Adaptable:** `MainUI.apply_layout(ancho)`: barra lateral (≥ 720 px, PC) o inferior con textos cortos (< 720 px, móvil); objetivos táctiles ≥ 48 px; teclado/ratón en PC; estiramiento `canvas_items` + `expand` y orientación por sensor en `project.godot`. Tablas con desplazamiento horizontal; todo texto con ajuste de línea.
- **Siempre visible:** modo libre vs reglamentado y perfil (con «PRUEBA» si es ilustrativo) en la barra de estado y junto a cada coste.
- **Visor:** tarjetas con retrato, vida, iniciativa, recursos y estados; previsión de turnos; registro seleccionable; inspector; deslizador de posición; controles de reproducción.
- **Informes nativos:** `ReportView` pinta el mismo `ReportDocument` que usan MD/HTML (tablas, barras con intervalos y histogramas dibujados con `_draw`).
- **Retratos opcionales** (`PortraitProvider`): `assets/portrait.(png|jpg|webp)` del paquete o **sustituto determinista** (color por id).
- **Localización por recursos** (`content/locale/es.json`, `en.json`; `LocaleService`): claves estables (`nav.library`), español inicial y inglés; se registra una `Translation` por idioma (`tr()` de Godot funciona); clave ausente ⇒ español ⇒ la propia clave. IDs técnicos del contenido en inglés, sin tocar.
- **Pruebas de interfaz:** las escenas se instancian en headless (`MainUI.build_ui()` explícito, porque el árbol no está inicializado durante `_init` del ejecutor) y se manejan emitiendo las señales de sus controles.

## 3b. Maquetación en pantallas estrechas (auditoría sin pantalla, `test_layout.gd`)
Medida con `get_combined_minimum_size` a 360 px: la navegación inferior pedía **585 px** y varias pantallas 350–620 px (botones de biblioteca con texto largo, casillas, filas de controles). Corregido: la navegación es un `FlowContainer` (se parte en filas; `vertical` en ancho), `UIKit.row` es un `HFlowContainer`, los botones y casillas **ajustan el texto** (`autowrap`), las líneas del registro del visor miden 48 px. Una prueba recorre las 10 pantallas a 360 px y exige: ningún control hoja con mínimo mayor que el ancho, objetivos táctiles ≥ 48 px (se excluyen los controles internos de Godot) y todas las pantallas alcanzables. **No sustituye a una prueba visual real.**

## 4. Límites conocidos
- **Sin prueba visual ni en dispositivo:** este entorno no tiene pantalla (ni Xvfb), así que el aspecto real, el tamaño de fuentes y el comportamiento táctil **no se han visto**; se verifican estructura, flujo, adaptabilidad lógica y textos. El APK sigue sin ejecutarse en dispositivo (fase 10).
- Selector de archivos (fase 10): diálogo nativo/`FileDialog`/bandeja de entrada (`docs/PLATFORMS.md`); el comportamiento real en Android no está probado en dispositivo.
- Los gráficos son `_draw` simples; el visor no anima (muestra estados por pasos).
- La reconstrucción hacia atrás rejuega desde el inicio (O(pasos)); el deslizador de un combate muy largo puede tardar.
- Una sola ventana, sin pestañas múltiples de visores; el depurador muestra el estado como JSON de solo lectura (sin árbol navegable).
- Importar bundles requiere que los paquetes referenciados quepan en 16 MB.
