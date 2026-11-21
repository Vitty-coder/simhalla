# USER_GUIDE — Guía de uso

Simhalla funciona **sin conexión**. Todo se guarda en `user://simhalla` (en Linux, `~/.local/share/godot/app_userdata/`; en Android, el almacenamiento privado de la app). Idiomas: español e inglés (Ajustes).

## Primeros pasos
1. Abrir la app. Con la **Biblioteca** vacía, pulsar **Instalar ejemplos** (también en Ajustes): se importan 6 paquetes de demostración.
2. **Duelo**: elegir dos contendientes, reglamento, perfil y semilla. La pantalla muestra, antes de combatir, la versión y huella exactas y el coste. Pulsar iniciar.
3. **Visor**: pausa/reanudar, velocidad, avanzar por acción o turno, retroceder, repetir con la misma semilla, inspeccionar un evento (cadena causal, fórmulas, tiradas). Se puede guardar el combate (queda fijado y es reproducible).
4. **Lotes**: 7 modalidades de simulación con semillas derivadas; progreso y cancelación. Guardar e **Informes** (Markdown, JSON o HTML; verificables).

## Importar contenido
- Pantalla **Importar**: escribir una ruta o pulsar **Examinar…** (diálogo del sistema o de Godot).
- En móviles sin selector, copiar los paquetes (carpeta, `.zip`) o bundles `.simbundle` a la **bandeja de entrada** `user://simhalla/inbox`; aparecen en la lista de la pantalla.
- Se muestra una vista previa con errores/avisos y la política ante colisiones (rechazar o guardar como versión nueva).

## Modos
**Libre** (sin límites de coste) o **reglamentado** (presupuesto con un perfil de costes). El perfil incluido es **ilustrativo/de PRUEBA**; el modo y el perfil están siempre visibles.

## Comprobar una plataforma
Pantalla **Plataforma** → Ejecutar: compara aritmética, RNG, hashes y duelos de referencia con los valores esperados y mide rendimiento. En PC: `simhalla.x86_64 -- --selftest`. Detalle y límites: `docs/PLATFORMS.md`.

## Límites
Sin prueba visual real ni en dispositivo Android; ver `docs/ROADMAP.md`.
