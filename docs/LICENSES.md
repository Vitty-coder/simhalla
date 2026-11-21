# LICENSES — Licencias y atribuciones

Simhalla se desarrolla y funciona **sin servicios de pago ni red** (PROJECT.md §17.1). Resumen de componentes:

| Componente | Uso | Licencia |
|---|---|---|
| **Godot Engine 4.7.2** (motor, plantillas de exportación) | Motor de aplicación; se redistribuye dentro de los exportados | **MIT** (https://godotengine.org/license; incluye componentes de terceros con licencias permisivas listadas en el propio editor: *Help → Third-party Licenses*) |
| Código y datos de este repositorio (`src/`, `content/`, `schemas/`, `tests/`, `tools/`, `docs/`) | Aplicación | Propios del proyecto (sin activos de terceros) |
| Paquetes de ejemplo (`content/packages/*`) | Demostración | CC0-1.0 (declarado en cada `manifest.json`) |
| Retratos | Sustituto generado por código (`PortraitProvider`) | Sin activos externos |
| Fuentes | Fuente por defecto de Godot (Open Sans, Apache-2.0, incluida en el motor) | Apache-2.0 |
| JDK 17 (Temurin), Android SDK, build-tools | **Solo para compilar** el APK; no se redistribuyen | GPLv2+CE / Apache-2.0 / licencias del SDK de Android |

- No hay imágenes, fuentes, sonidos ni bibliotecas de terceros en el repositorio (una prueba lo comprueba), por lo que no hay atribuciones adicionales.
- No se publica en tiendas ni se introduce cuota de tienda (PROJECT.md §17.1); si se decidiera, habría que comprobar costes y condiciones por separado.
- La clave de firma del APK local es de **depuración** (distribución local); una publicación necesitaría una clave propia.
