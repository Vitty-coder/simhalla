# PACKAGES — Paquetes de contenido (fase 2)

Un **paquete** es una carpeta o un `.zip`/`.simpkg` con archivos JSON UTF-8. Se
**valida por completo antes de incorporarse** a la biblioteca, que guarda
versiones **inmutables** identificadas por `id@version` y una huella SHA-256.
Los esquemas públicos están en [`schemas/`](../schemas) (JSON Schema, un subconjunto
documentado en `src/content/schema_validator.gd`). **No invente campos:** cualquier
propiedad no listada se rechaza con `propiedad desconocida`.

## 1. Tipos de paquete y archivos

| Tipo (`manifest.type`) | Obligatorio | Opcional | Dependencias |
|---|---|---|---|
| `character` | `manifest.json`, `character.json` | `abilities.json`, `resources.json`, `ai.json` (`ai`), `artifact.json`, `effects.json` (estados propios), `summons.json` (plantillas), `README.md`, `assets/*.{png,jpg,jpeg,webp}` | sí (`abilities`, `ai`) |
| `abilities` (biblioteca) | `manifest.json`, `abilities.json` | `README.md` | no |
| `ai` (biblioteca) | `manifest.json`, `ai.json` (`strategies`) | `README.md` | no |

Los **personajes** admiten `scripts/<id>.sim` (SimScript, ver `SCRIPTING_API.md`; solo se **compilan** al importar, **nunca se ejecutan**; `[script]` por nombre/extensión inválidos, `[codificacion]` por BOM o no-UTF-8). Rechazados con `[no_soportado]`: `scripts/**` en paquetes de biblioteca y `effects.json`/`summons.json` dentro de paquetes de **biblioteca** (solo los personajes los definen). Cualquier otro archivo: `[archivo_desconocido]`.

Valoración opcional (fase 6): `PackageImporter.balance = {"profile", "mode", "budget"}` añade el informe a `ImportReport.balance`; en modo `regulated` un paquete fuera de presupuesto o no evaluable se rechaza con `[equilibrio]` (ver `BALANCE_RULES.md`).

## 2. Archivos

| Archivo | Esquema | Contenido |
|---|---|---|
| `manifest.json` | `manifest.schema.json` | `schema`=`simhalla.manifest/1`, `id` (`namespace/nombre`, minúsculas/`_`), `version` (semver), `type`, `name`, opc.: `description`, `author`, `license`, `min_engine_version`, `dependencies:[{id, version}]` |
| `character.json` | `character.schema.json` | `schema`, `name`, `tags`, `stats`, `basic_attack`, `counts_for_victory`, `imports:[{package, version, abilities:[ids]}]`, `ai_ref:{package, version, strategy}` |
| `abilities.json` | `abilities.schema.json` | `abilities:[…]` (ver `ABILITY_REFERENCE.md`) |
| `resources.json` | `resources.schema.json` | `resources:{id:{initial,min,max}}` |
| `ai.json` | `ai.schema.json` | personaje: `ai:{…}`; biblioteca de IA: `strategies:{id:{…}}` (ver `AI_REFERENCE.md`) |
| `effects.json` | `effects.schema.json` | `statuses:[…]` (estados propios, incluidas formas; ver `ABILITY_REFERENCE.md` §3) |
| `summons.json` | `summons.schema.json` | `summons:{id: plantilla}` |
| `artifact.json` | `artifact.schema.json` | `id`, `name`, `modifiers:[{stat, kind: set|flat|pct_add|mult|min|max, value, priority}]`, `abilities:[…]`, `resources`, `statuses`, `summons`, `ai_rules` |

El **artefacto** (único, opcional) aplica modificadores de estadísticas con origen `artifact:<id>` (la base no cambia) y aporta habilidades. Sus habilidades pueden ser pasivas o reacciones; también aporta recursos, estados, invocaciones y reglas de IA propios (ver `ABILITY_REFERENCE.md` §6). Scripts del artefacto: fase 5.

`id` de entidad en combate = `manifest.id` (se puede cambiar con `overrides.id` para duelos espejo); el equipo (`team`) lo decide quien monta el combate (`overrides.team`).

## 3. Versiones y dependencias

- Semver `MAJOR.MINOR.PATCH[-pre]`. Restricciones: `*`, `1.2.3`, `^1.2.3`, `~1.2.3`, `>=1.2.3`. Se resuelve la **versión más alta** que cumple; las prereleases solo si se piden expresamente.
- Todo paquete usado en `imports`/`ai_ref` debe estar declarado en `manifest.dependencies` y existir **ya** en la biblioteca (por construcción no hay ciclos; la autodependencia y los duplicados se rechazan). Una dependencia declarada y no usada genera un aviso.
- Importar **otra versión** crea una entrada nueva; **mismo `id@version` con contenido distinto = error `[version_conflicto]`**; mismo contenido = idempotente. Nunca se sobrescribe lo necesario para reproducir combates antiguos.
- Cada combate registra en `combat_started` la `content_ref` de cada entidad (`id`, `version`, `hash`, dependencias exactas con su huella). Fijar la versión (`version: "1.0.0"`) reproduce un combate antiguo aunque existan versiones nuevas.
- Al cargar de la biblioteca se **recalcula la huella**: un archivo alterado se rechaza (`[integridad]`).

## 4. Seguridad de importación (todas con pruebas)

Rutas con `..`, absolutas, `\`, `:`, NUL o segmentos vacíos (`[path_traversal]`); colisiones por mayúsculas/duplicados; enlaces simbólicos; > 256 archivos, > 2 MiB por archivo, > 16 MiB en total; **bombas ZIP** (los tamaños se leen del directorio central *antes* de extraer; ratio > 200:1 rechazado); ZIP corrupto; JSON inválido (con línea), BOM, no-UTF-8; esquemas; assets con extensión y firma comprobadas (SVG no admitido); ejecución de scripts durante la importación: imposible (no se importan).

## 5. Herramientas

```bash
# validar sin almacenar / importar / listar (biblioteca por defecto: user://library)
godot --headless --path . --script res://tools/package_tool.gd -- validate <ruta>
godot --headless --path . --script res://tools/package_tool.gd -- import <ruta> [<ruta>…] [--library dir]
godot --headless --path . --script res://tools/package_tool.gd -- list [--library dir]
# duelo con paquetes importados
godot --headless --path . --script res://tools/run_duel.gd -- pkg:examples/arcane_duelist pkg:examples/iron_vanguard@^1.0.0 42 --log
```
Código de salida 2 = paquete rechazado. Los errores llevan `archivo: [código] ruta: mensaje`.

Paquetes de ejemplo validados en la suite: `content/packages/{core_spells, basic_ai, arcane_duelist, iron_vanguard}` (importar primero las bibliotecas).

## 6. Migración de esquemas

Cada archivo declara `schema: "simhalla.<tipo>/<N>"`. Un valor distinto del soportado se rechaza con `debe valer 'simhalla.<tipo>/1'`. Cuando exista la versión 2 se añadirá un migrador explícito y se documentará aquí; no se interpretan versiones desconocidas.

## 7. Limitaciones conocidas

Sin firma/autoría verificada, sin índices persistentes ni historial/exportación portable de la biblioteca (fase 9), sin dependencias entre bibliotecas, sin catálogo de elementos validado, sin evaluación de costes (fase 6).
