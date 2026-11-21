# schemas/

Esquemas públicos versionados (JSON Schema, draft 2020-12) de los archivos de paquete.
Describen el formato **implementado**; ver `docs/PACKAGES.md` y `docs/DATA_SCHEMAS.md`.

| Archivo | Valida | `schema` |
|---|---|---|
| `manifest.schema.json` | `manifest.json` | `simhalla.manifest/1` |
| `character.schema.json` | `character.json` | `simhalla.character/1` |
| `abilities.schema.json` | `abilities.json` | `simhalla.abilities/1` |
| `resources.schema.json` | `resources.json` | `simhalla.resources/1` |
| `ai.schema.json` | `ai.json` | `simhalla.ai/1` |
| `artifact.schema.json` | `artifact.json` | `simhalla.artifact/1` |
| `effects.schema.json` | `effects.json` (estados propios) | `simhalla.effects/1` |
| `summons.schema.json` | `summons.json` (plantillas de invocación) | `simhalla.summons/1` |
| `report.schema.json` | modelo de informes (`simhalla.report/1`) | `simhalla.report/1` |
| `batch.schema.json` | planes de lote (`content/batches/*.json`) | `simhalla.batch/1` |
| `balance.schema.json` | perfiles de equilibrio (`content/balance/*.json`) | `simhalla.balance/1` |
| `common.schema.json` | definiciones compartidas | — |

El validador del motor (`SchemaValidator`) implementa un subconjunto de JSON Schema; una validación semántica adicional
(fórmulas, referencias, costes, IA) corre después y no se expresa en estos esquemas. Cambiar un esquema exige subir su `/N`
y documentar la migración.
