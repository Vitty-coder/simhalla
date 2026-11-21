# DATA_SCHEMAS — Formatos de datos implementados (fase 1)

> **Migraciones de esquema** (`SchemaMigrator`): cada dato declara `simhalla.<familia>/<N>`. Una versión menor se migra en cadena **solo en memoria** con pasos registrados (los archivos y huellas no se reescriben); una versión mayor se rechaza con `[schema_futuro]`; un paso que falta da `[migracion_ausente]`. Se aplica al importar y cargar paquetes, ajustes, historial, índices de registros y manifiestos de bundle. Hoy todas las familias están en `/1`, así que no hay pasos reales: el mecanismo está probado con pasos de prueba. Antes de publicar un `/2` hay que registrar su paso **y** actualizar el JSON Schema público de la familia.

> Solo se documentan campos **realmente soportados**. Un campo no listado aquí
> no existe: una IA creadora de contenido **no debe inventarlo** (las propiedades
> desconocidas se rechazan). Los **paquetes** (manifiesto, esquemas públicos en
> `schemas/`, dependencias, ZIP) están en [`PACKAGES.md`](PACKAGES.md). Este
> documento describe el formato de la **entidad ya compuesta** (que es lo que
> consume el motor) y de reglamento/perfil.

Todos los ficheros son JSON UTF-8. Los números JSON se interpretan como `float`.

## 1. Reglamento (`content/rulesets/*.json`)

Las claves ausentes toman el valor por defecto (fusión recursiva). Valores por defecto en `content/rulesets/default_ruleset.json`.

| Clave | Tipo / valores | Defecto | Significado |
|---|---|---|---|
| `id`, `version` | string | `default_ruleset`, `0.1.0-provisional` | Identidad (van al resultado del combate) |
| `atb.initiative_threshold` | número > 0 | 1000 | Umbral de turno |
| `atb.tie_break` | lista de `initiative_excess_desc`,`spd_desc`,`slot_asc`,`random` | excedente, spd, slot | Desempate (en orden) |
| `atb.timed_events_first` | bool | true | Evento temporizado antes que turno en el mismo instante |
| `atb.non_positive_spd` | `clamp_zero` | `clamp_zero` | Política SPD ≤ 0 |
| `turn.main_actions_per_turn` | entero ≥ 0 | 1 | Acciones principales por turno |
| `turn.max_actions_per_turn` | entero ≥ 1 | 20 | Límite técnico (techo duro 100) |
| `damage.rounding.mode` | `none,round,floor,ceil,trunc` | `round` | Redondeo |
| `damage.rounding.decimals` | 0–9 | 0 | Decimales |
| `damage.min_effective_defense` | número > −100 | 0 | Suelo de la defensa efectiva |
| `damage.min/max_elemental_resistance` | números (min ≤ max) | −1 / 1 | Cotas de resistencia elemental |
| `damage.roll_scope` | `per_action`,`per_component` | `per_action` | Alcance de tiradas |
| `damage.survive_hp` | número | 1 | Vida tras prevenir una muerte |
| `hit.min_chance/max_chance` | números | 0 / 1 | Cotas de P(impacto) |
| `hit.min_crit_chance/max_crit_chance` | números | 0 / 1 | Cotas de P(crítico) |
| `basic_attack.{id,name,damage_type,element,formula,can_crit}` | ver §3 | físico, `caster.ATK` | Ataque básico universal |
| `victory.simultaneous_death` | `draw` | `draw` | Muerte simultánea |
| `victory.limits.{max_virtual_time,max_turns,max_actions,stagnation_turns}` | números > 0 | 10000/1000/5000/50 | Límites |
| `victory.limit_resolution` | `draw`,`highest_hp_ratio` | `draw` | Resolución al alcanzar un límite |
| `ai.failure_policy` | `wait` | `wait` | Fallback de IA |
| `ai.visible_fields` | subconjunto de `hp,hp_max,initiative,resources,statuses` | todos | Lo que la IA ve de los demás |
| `safety.max_events`, `safety.max_event_depth` | enteros ≥ 1 | 200000 / 32 | Límites técnicos (techos duros 5 000 000 / 64) |
| `safety.max_reaction_chain`, `safety.max_scheduled` | enteros ≥ 1 | 4 / 1000 | Cadena de reacciones / efectos programados (techos 8 / 10 000) |
| `scripting.max_instructions`, `max_call_depth`, `max_collection`, `max_string`, `max_mutations`, `max_source_bytes`, `max_ast_nodes` | enteros ≥ 1 | 20000 / 16 / 256 / 256 / 32 / 16384 / 3000 | Límites de SimScript (techos duros en `ScriptLimits.CEILINGS`) |
| `elements` | lista de identificadores | fire, water, earth, air, lightning, ice, light, dark | Catálogo elemental (validado) |
| `summons.max_per_owner`, `summons.max_entities` | enteros | 8 / 64 | Límites de invocaciones (techo total 256) |
| `summons.on_owner_death` | `despawn`,`stay` | `despawn` | Qué pasa con las invocaciones al morir el dueño |

## 2. Perfil de equilibrio (`content/balance/*.json`)

```json
{"id": "technical_profile", "version": "0.1.0", "illustrative": true,
 "base_stats": {"HP": 1000, "ATK": 100, "...": 0}}
```
`base_stats` = estadísticas gratuitas con las que parte todo PJ. En la fase 1 **no hay costes ni presupuestos** (fase 6).

Perfiles con modelo de costes (fase 6): ver `BALANCE_RULES.md` y `schemas/balance.schema.json` (`content/balance/reference_costs.json`, ilustrativo). Claves nuevas del perfil: `budgets`, `default_budget`, `rounding`, `credit_cap`, `costs`; el perfil técnico (solo `base_stats`) sigue siendo válido.

Planes de lote (fase 7): ver `SIMULATION.md` y `schemas/batch.schema.json` (`content/batches/*.json`).

## 3. Entidad / personaje (`content/fixtures/entities/*.json`)

```json
{
  "id": "glass_cannon", "name": "Canon de cristal", "team": "A",
  "tags": ["fixture", "magic"],
  "stats": {"HP": 600, "MAG": 220, "SPD": 140, "CRIT": 0.25, "ELEM_AFF.fire": 0.2},
  "resources": {"mana": {"initial": 60, "max": 60, "min": 0}},
  "basic_attack": true,
  "abilities": [ { "...": "ver §4" } ],
  "ai": {"type": "priority_list", "rules": [ { "...": "ver AI_REFERENCE.md" } ]}
}
```
| Campo | Obligatorio | Notas |
|---|---|---|
| `id` | sí | Único en el combate. `overrides` de `DuelRunner` pueden cambiar `id`/`team` |
| `team` | sí al combatir | Equipos distintos se enfrentan (≥ 2 equipos) |
| `name`, `tags` | no | `tags`: lista de strings |
| `stats` | no | Sobrescribe la base gratuita; **cualquier** id es válido (estadísticas personalizadas); `ELEM_AFF.<elem>` / `ELEM_RES.<elem>` |
| `resources` | no | `{id: {initial, min=0, max, regen_per_turn}}`; por defecto sin máximo; `initial` por defecto = `max` si existe |
| `basic_attack` | no (true) | Si true se añade la habilidad del reglamento (`basic_attack`) |
| `abilities` | no | Lista de habilidades (§4) |
| `ai` | no | Si falta: atacar con el ataque básico si lo tiene; si no, esperar |
| `counts_for_victory` | no (true) | `false` para auxiliares/invocaciones |
| `statuses` | no | Lista de estados propios (ver `ABILITY_REFERENCE.md` §3) |
| `summons` | no | `{id: plantilla}` (ver `ABILITY_REFERENCE.md` §4) |
| `scripts` | no | `{id: código SimScript}` (≤ 32; en paquetes, `scripts/<id>.sim`). Se compilan al construir; ver `SCRIPTING_API.md` |
| `artifact` | no | `{id, name?, modifiers:[{stat, kind, value, priority?}], abilities:[…], resources, statuses, summons, ai_rules}`; `kind`: `set,flat,pct_add,mult,min,max` |

## 4. Habilidad

```json
{"id": "fireball", "name": "Bola de fuego", "action_type": "main",
 "targeting": "enemy", "target_count": 1, "cost": {"mana": 20}, "tags": ["spell","fire"],
 "effects": [ {"type": "damage", "...": "..."} ]}
```
- `action_type`: `main` | `free` | `reaction` (las reacciones aún no se ejecutan: fase 3).
- `targeting`: `enemy` | `ally` (aliados sin el propio) | `self` | `any`.
- `cost`: `{recurso: cantidad}`; el recurso debe existir en la entidad.
- `effects`: lista de operaciones (ver `ABILITY_REFERENCE.md`).

## 5. Resultado de combate (`CombatResult.to_dict()`)

`outcome` (`win|draw|aborted`), `winner_team`, `reason`, `kind` (`victory|limit|stalemate|technical|cancelled`), `error`, `seed`, `engine_version`, `ruleset{id,version,hash}`, `end_time`, `turns`, `actions`, `events`, `log_hash`, `entities{id:{team,alive,hp}}`, `stats{id:{…}}`.
