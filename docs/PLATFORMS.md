# PLATFORMS — Plataformas, exportación, conformidad y distribución local (fase 10)

Simhalla se distribuye **localmente y sin red**: un binario de Linux x86_64 y un APK de Android arm64. No hay tiendas, servicios de pago ni código de red (una prueba audita `src/` y `tools/`). Licencias: `docs/LICENSES.md`.

## Requisitos para compilar
- Godot 4.7.2 con plantillas de exportación (`~/.local/share/godot/export_templates/4.7.2.stable/`).
- Android: JDK 17, Android SDK (build-tools, platform 36), clave de depuración; variables en `~/tools/android/build.env`.

## Compilar y verificar
```
tools/run_tests.sh                    # 445 casos
tools/build_linux.sh release          # build/linux/simhalla.x86_64 (~74 MB, PCK embebido)
tools/verify_export.sh linux          # ejecuta el exportado en un directorio vacío con --selftest
tools/build_android.sh debug          # build/simhalla-debug.apk (~29 MB, solo arm64-v8a)
tools/release_check.sh                # todo lo anterior de una vez
tools/verify_export.sh android        # firma (apksigner), permisos, arquitecturas y contenido
```
El APK **no solicita ningún permiso** (ni INTERNET) y excluye `tests/`, `tools/`, `docs/`; incluye `*.json`, `*.sim`, `*.md` (paquetes, esquemas, localización, scripts, conformidad).

## Conformidad multiplataforma (determinismo)
`PlatformCheck` (pantalla **Plataforma** en la app, o `--selftest` por línea de órdenes) compara la plataforma actual con valores generados en la referencia (Linux x86_64, `content/conformance/expected.json`):
vectores bit a bit de aritmética/`libm`, RNG SplitMix64, SHA-256, fórmulas y formatos; 6 duelos de referencia (hash del registro, resultado, turnos, eventos, tiempo final); hashes de los paquetes de ejemplo; almacenamiento; hilos (síncrono == 2 hilos); y un **flujo de aplicación de extremo a extremo** en el propio dispositivo (`flow`: ejemplos → duelo → guardado → reproducción → informe verificado → bundle → importación en otra instalación → reproducción idéntica), de modo que Android/PC comprueban también la capa de aplicación y no solo el motor. Los bancos de rendimiento informan sin puntuar.
- Ejecutar en un dispositivo: abrir **Plataforma → Ejecutar**; el informe se guarda en `<almacenamiento>/platform/` (JSON + MD). En PC: `simhalla.x86_64 -- --selftest` (código de salida ≠ 0 si hay incompatibilidad).
- Tras cambiar el motor/golden: `tools/regen_golden.sh` y `godot --headless --script tools/gen_conformance.gd`, y subir `ENGINE_VERSION`.

## Selección de archivos
`FilePicker`: diálogo nativo si existe; si no, `FileDialog` de Godot en escritorio; en móvil sin diálogo, **bandeja de entrada** `user://simhalla/inbox` (copiar allí paquetes/zip/`.simbundle`). Los ejemplos incluidos se instalan desde la biblioteca vacía o Ajustes.

## Rendimiento medido (Linux x86_64, host compartido, traza completa)
| Escenario | Duelos/s | Eventos/s |
|---|---:|---:|
| simple | ≈ 26–36 | ≈ 10 600 |
| effects | ≈ 10 | ≈ 7 700 |
| summons | ≈ 12–14 | ≈ 8 100 |
Objetivos **provisionales** (D-116, `content/conformance/targets.json`; informativos): escritorio 15 / 5 / 6 duelos/s; móvil 5 / 2 / 2 (estimación sin medir en dispositivo). La pantalla Plataforma y `--selftest` muestran «Objetivo» y «Cumple».

Perfilado: `JSON.stringify` del evento ≈ 40 µs de ≈ 198 µs/evento (efectos). No se optimizó para no alterar el formato canónico de hash (rompería golden y conformidad); queda como mejora posible.

## Qué NO está verificado (límites honestos)
- **El APK no se ha ejecutado en ningún dispositivo ni emulador** (no hay KVM/arm64 en este entorno). Solo se verificó estructura, firma, permisos y contenido.
- **Determinismo PC↔Android no verificado**: la batería de conformidad existe y debe ejecutarse en un dispositivo real; hasta entonces es una hipótesis.
- Interfaz sin prueba visual ni táctil real; rendimiento en Android sin medir; `user://` en Android sin probar.
- Clave de firma de depuración (distribución local).
