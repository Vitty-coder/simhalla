# AI_CREATOR_KIT — Guía autosuficiente para que una IA cree personajes de Simhalla

> **Cómo usar este documento:** pégalo (entero) como instrucciones/contexto a la IA creadora, junto con la tarea («crea un personaje …»). Todo lo que
> necesita está aquí o en los archivos que menciona. **No inventes campos, operaciones ni valores:** el importador rechaza cualquier propiedad
> desconocida. Si algo no está en esta guía, no existe. Idioma de los textos del juego: español (`name`, `description`); los **ids** son técnicos
> (minúsculas, dígitos y `_`).

## 0. Qué debes entregar

Un **paquete de personaje** = una carpeta (o `.zip`) con archivos **JSON UTF-8 sin BOM, sin comentarios y sin comas finales**. Cada archivo lleva
`"schema"` con el valor exacto indicado. Entrega los archivos completos, uno por bloque, con su nombre. No añadas texto dentro de los JSON.

```
mi_personaje/
├── manifest.json     (obligatorio)  identidad y dependencias
├── character.json    (obligatorio)  estadísticas, etiquetas, imports, ai_ref
├── abilities.json    (opcional)     habilidades PROPIAS del personaje
├── resources.json    (opcional)     recursos (maná, energía…)
├── effects.json      (opcional)     estados PROPIOS (veneno, escudo, formas…)
├── summons.json      (opcional)     plantillas de invocación
├── ai.json           (opcional)     la IA del personaje (si falta, solo ataca)
├── artifact.json     (opcional)     un artefacto (modificadores + habilidades)
├── scripts/*.sim     (opcional)     SimScript — evítalo salvo necesidad real (§10)
└── README.md         (opcional)
```

> ⚠ **Error nº 1 de las IAs:** las habilidades NO van dentro de `character.json`. `character.json` solo admite
> `schema, name, tags, stats, basic_attack, counts_for_victory, imports, ai_ref`. Habilidades → `abilities.json`; IA → `ai.json`; recursos → `resources.json`.

## 1. Modelo mental del combate (lo mínimo para diseñar bien)

- **ATB determinista:** cada entidad gana iniciativa a ritmo de su `SPD`; al llegar al umbral (1000) actúa. Más `SPD` = más turnos. Sin azar oculto:
  misma semilla ⇒ mismo combate. El azar (impacto, crítico, `chance`) usa un RNG con semilla.
- **Un turno = una acción principal** (`action_type: main`) + las `free` que permita su límite. Las `reaction` se disparan fuera de turno por eventos.
- **Daño:** `fórmula` → defensa (`DEF` físico, `RES` mágico) → afinidad/resistencia elemental → redondeo. `true` ignora defensa. El crítico usa
  `CRIT`/`CRIT_DMG`; el impacto, `ACC` contra `EVA`.
- **Victoria:** queda un único equipo con entidades vivas que cuentan para la victoria. Límites técnicos (turnos/tiempo/estancamiento) ⇒ empate.
- **La IA solo propone**; el motor revalida (coste, cooldown, objetivo). Una IA mala = personaje malo aunque sus habilidades sean buenas.

## 2. `manifest.json`

```json
{"schema": "simhalla.manifest/1", "id": "mi_espacio/mi_heroe", "version": "1.0.0", "type": "character",
 "name": "Mi héroe", "description": "Qué es y qué hace.", "author": "Quien sea", "license": "CC0-1.0",
 "dependencies": [{"id": "templates/library_abilities", "version": "^1.0.0"}]}
```
- `id`: `espacio/nombre` en minúsculas. `version`: semver `1.0.0`. `type`: `character` | `abilities` | `ai`.
- `dependencies`: **todo** paquete que uses en `imports`/`ai_ref` debe declararse aquí y existir ya en la biblioteca (una dependencia sin usar da aviso).
- Cambiar el contenido de un `id@version` ya importado es un error (`[version_conflicto]`): **sube la versión** (`1.0.1`).

## 3. `character.json`

```json
{"schema": "simhalla.character/1", "name": "Hechicera", "tags": ["human", "mage"],
 "stats": {"HP": 800, "MAG": 170, "DEF": 80, "RES": 130, "SPD": 105, "CRIT": 0.15, "ELEM_AFF.fire": 0.1},
 "basic_attack": true,
 "imports": [{"package": "templates/library_abilities", "version": "^1.0.0", "abilities": ["power_strike"]}],
 "ai_ref": {"package": "templates/library_ai", "version": "^1.0.0", "strategy": "bruiser"}}
```
**Estadísticas** (solo indica las que cambian; el resto toma la base gratuita):

| Stat | Base | Significado / rango útil |
|---|---|---|
| `HP` | 1000 | vida máxima (500–2500) |
| `ATK` / `MAG` | 100 | poder físico / mágico (60–250) |
| `DEF` / `RES` | 100 | mitigación física / mágica (40–300) |
| `SPD` | 100 | ritmo de turnos (60–160) |
| `ACC` | 1.0 | precisión (1.0 = 100 %) |
| `EVA` | 0.10 | evasión (0–0.5) |
| `CRIT` / `CRIT_DMG` | 0.10 / 1.5 | prob. y multiplicador de crítico (0–0.6 / 1.5–3) |
| `HEAL_REC` | 1.0 | multiplicador de curación recibida |
| `ELEM_AFF.<elem>` / `ELEM_RES.<elem>` | 0 | afinidad (+daño) / resistencia (−daño recibido), −1…1 |

Elementos válidos por defecto: `fire, water, earth, air, lightning, ice, light, dark`. Cualquier otro id de stat es una estadística personalizada
(útil para fórmulas). `basic_attack: true` añade el ataque básico universal (`basic_attack`, físico `caster.ATK`), **gratuito**, usable desde la IA.

## 4. Recursos (`resources.json`)

```json
{"schema": "simhalla.resources/1", "resources": {"mana": {"initial": 80, "min": 0, "max": 80, "regen_per_turn": 6}}}
```
Toda habilidad con `cost: {"mana": 20}` necesita que el recurso exista. `regen_per_turn` evita quedarse sin recursos para siempre.

## 5. Habilidades (`abilities.json`)

```json
{"schema": "simhalla.abilities/1", "abilities": [
  {"id": "meteor", "name": "Meteoro", "action_type": "main", "targeting": "enemy", "cost": {"mana": 45}, "cooldown": 3, "tags": ["spell", "fire"],
   "effects": [{"type": "damage", "components": [{"damage_type": "magical", "element": "fire", "formula": "caster.MAG * 2.6", "pen_pct": 0.15}], "can_crit": true}]}
]}
```
| Campo | Valores / notas |
|---|---|
| `id`, `name` | `id` único en el personaje |
| `action_type` | `main` (1 por turno) · `free` (**acótala** con `uses_per_combat`/`cooldown`) · `reaction` (fuera de turno, **requiere `trigger`**) |
| `targeting` | `enemy` · `ally` · `self` · `any` |
| `cost` | `{recurso: cantidad}` (se paga al comprometer la acción) |
| `cooldown` | número de turnos propios, u objeto duración (§7) |
| `uses_per_combat`, `uses_per_turn`, `charges` | límites de uso |
| `requires` | condiciones: `{"self.hp_ratio": {"lt": 0.5}, "target.status.stun": {"ge": 1}}` (ops `lt le gt ge eq ne`) |
| `trigger` | convierte la habilidad en **disparada** (reacción/automática); la IA **no** la elige. `{"event": "damage_dealt", "when": {...}, "target": "event_source", "chance": 0.35, "limit_per_turn": 1}`. `target` ∈ `self, event_source, event_target, lowest_hp_enemy, first_enemy, random_enemy` |
| `passive` | `{"modifiers": [{"stat": "RES", "kind": "flat", "value": 25}]}` permanente (usa `"effects": []`) |
| `cast_time` | canalizada: los efectos ocurren tras N unidades de tiempo |
| `tags` | etiquetas libres (las usan estados y bloqueos) |

### Operaciones de efecto (`effects[].type`) — la lista COMPLETA
Comunes: `"on"` ∈ `targets` (defecto), `caster`, `all_enemies`, `all_allies`, `random_enemy`, `random_ally`, `lowest_hp_enemy`; `"chance"` 0..1 (una tirada por objetivo).

| `type` | Campos |
|---|---|
| `damage` | `components[]` {`damage_type`: `physical`\|`magical`\|`true`, `element`, `formula`, `pen_flat`, `pen_pct`, `elem_pen`}, `always_hit`, `can_crit`, `crit_bonus` |
| `heal` | `formula`, `can_crit` |
| `apply_status` | `status`, `stacks`, `duration`, `magnitude` (número o fórmula) |
| `remove_status` | `status` \| `tags[]` \| `beneficial`, `count`, `force` |
| `extend_status` | `status` \| `tags[]`, `amount` (±) |
| `invert_status` | `status` \| `tags[]` \| `beneficial`, `count` |
| `propagate_status` | `status` \| `tags[]`, `to`: `target_allies,target_enemies,caster_allies,caster_enemies,all_others,random_other`, `count` |
| `transfer_status` | `mode`: `steal`\|`copy`\|`give`, filtro, `count` |
| `modify_resource` | `resource`, `amount`, `mode`: `add`\|`set`, `property`: `value`\|`max` |
| `modify_initiative` | `mode`: `add,set,steal,extra_turn`, `amount` |
| `modify_cooldown` | `ability`, `mode`: `reduce,add,reset`, `amount` |
| `summon` | `template` (id en `summons.json`), `count` (1–8), `lifespan` (duración), `inherit.stat_pct` |
| `record_state` / `restore_state` | `key`, `what`: lista de `hp,resources,statuses`, `consume` |
| `delayed_effect` | `delay` (unidades de tiempo), `effects[]` |
| `repeat_action` / `copy_action` | `times` 1–3 / — (gratis) |
| `emit_event` / `metric` | `name`, `data` / `name`, `amount` |
| `script` | `script`, `args`, `contract` (§10) |

## 6. Fórmulas (gramática segura; **no** es código)

`+ - * / % ^`, paréntesis y funciones `min max clamp abs floor ceil round sqrt`. Máx. 512 caracteres.
Variables: `caster.<STAT>` y `target.<STAT>` (incluye `ELEM_RES.fire`…), `caster.hp`, `caster.hp_max`, `caster.hp_missing`, `caster.hp_ratio`,
`caster.res.<recurso>` / `caster.res.<recurso>.max`, y dentro de estados `status.stacks`, `status.magnitude`, `status.shield`.
Ejemplos válidos: `caster.ATK * 1.5` · `caster.MAG * 0.9 + caster.hp_missing * 0.2` · `min(300, caster.res.rage.max * 2)` · `status.stacks * 25`.
**Inválidos:** `if`, `&&`, comparaciones, variables inventadas (`self.ATK`), llamadas a funciones propias. División por cero = error de combate.

Orientación de escala (ilustrativa): un golpe básico ≈ `1.0 × stat`; una habilidad con cooldown 3 ≈ `2.0–2.8 × stat`; una curación ≈ `0.8–1.2 × MAG`.

## 7. Estados (`effects.json`) y duraciones

Nativos disponibles sin definir nada: `poison, burn, bleed, stun, silence, freeze, regen, taunt`. Para uno propio:

```json
{"schema": "simhalla.effects/1", "statuses": [
  {"id": "scorch", "name": "Abrasado", "tags": ["dot", "fire"], "beneficial": false, "dispellable": true,
   "stacking": {"policy": "stack_intensity", "max_stacks": 4}, "duration": 3,
   "modifiers": [{"stat": "DEF", "kind": "pct_add", "value": -0.05, "per_stack": true}],
   "periodic": [{"on": "turn_end", "effects": [{"type": "damage", "components": [{"damage_type": "magical", "element": "fire", "formula": "status.stacks * 25 + caster.MAG * 0.1"}]}]}]}
]}
```
- **Duración:** número = turnos del afectado; u objeto `{"unit": ..., "amount": N}` con `unit` ∈ `target_turns, caster_turns, global_actions, time, events, permanent`
  (en `summon.lifespan` solo `target_turns, global_actions, time, permanent`). El turno en que se aplica **no cuenta**.
- `stacking.policy` ∈ `stack_intensity, stack_duration, independent, refresh, replace, keep_strongest, ignore`.
- `modifiers[].kind` ∈ `set, flat, pct_add, mult, min, max` (`pct_add` 0.4 = +40 %; escala con pilas si `per_stack`).
- Extras: `flags` (`skip_turn, taunt, block_tags, block_action_types, immune_status_tags…`), `defense` (inmunidad, absorción, reducción, bloqueo, parada, reflejo,
  escudo, `prevent_death`), `on_apply/on_expire/on_death`, `form` (transformación: añade/quita habilidades y cambia la IA).

## 8. Invocaciones, artefacto y formas

- **`summons.json`:** `{"schema": "simhalla.summons/1", "summons": {"wolf": {"name": "...", "stats": {...}, "basic_attack": true, "ai": {...}, "abilities": [...], "counts_for_victory": false}}}`.
  Son entidades completas del equipo del invocador; máx. 8 por dueño, 64 en total; mueren con el dueño (`despawn`).
- **`artifact.json`:** `id`, `name`, `modifiers[]`, `abilities[]`, `resources`, `statuses`, `summons`, `ai_rules` (reglas de IA antepuestas). Uno por personaje.
- **Formas:** un estado con bloque `form` (§7) y el mismo `group` para que sean excluyentes.

## 9. IA (`ai.json`)

Forma: `{"schema": "simhalla.ai/1", "ai": {...}}` (o, en biblioteca, `"strategies": {nombre: {...}}` y el personaje usa `ai_ref`). **Si falta, el personaje solo ataca.**

| `type` | Cuándo usarlo |
|---|---|
| `passive` | no hace nada (dummy) |
| `priority_list` | **por defecto**: reglas en orden, gana la primera aplicable |
| `scored` | puntúa todas las opciones con pesos (`damage, lethal, heal, need, low_target, status, hit, cost, tempo`); `bias`, `modifiers`, `wait_below` |
| `state_machine` | fases (`attack` ⇄ `recover`) con `transitions` y estrategias por estado |
| `behavior_tree` | árboles `selector/sequence/condition/action/strategy/wait/not/succeed` |
| `script` | IA en SimScript (avanzado) |

Regla de `priority_list`: `{"ability": id, "target": ..., "when": {...}, "remember": {...}}`.
`target` ∈ `self, first_enemy, lowest_hp_enemy, highest_hp_enemy, lowest_hp_ally, first_ally, last_attacker`.
Rutas de `when` (todas deben cumplirse; sin dato visible = falso): `self.hp, self.hp_ratio, self.res.<id>, self.stat.<STAT>, self.status.<id>, mem.<var>,
enemy.alive_count, enemy.lowest_hp_ratio, ally.alive_count, ally.lowest_hp_ratio, turn, time, state_turns, target.hp, target.hp_ratio, target.res.<id>,
target.status.<id>, predict.damage, predict.lethal, predict.heal, predict.hit_chance, event.amount (solo reacciones)`.

**Reglas de oro de la IA:**
1. La última regla debe ser un **comodín** (`basic_attack`) para que nunca se quede esperando.
2. Ordena de **más específica/situacional a más general** (curar si está bajo → habilidad cara → barata → básico).
3. Toda habilidad referenciada debe existir (si no: error de validación). Las `reaction`/`trigger`/`passive` **no se listan** en la IA (se disparan solas).
4. Condiciona las habilidades con recursos/cooldown de modo que la IA no las intente cuando no son legales (si no son legales se descartan y se baja a la siguiente regla).
5. Usa `target.status.<id>` para no reaplicar un estado ya presente (p. ej. `{"target.status.poison": {"lt": 1}}`).

## 10. SimScript (evítalo por defecto)

Solo para mecánicas que no se pueden expresar con los efectos de §5 (cadenas, escalados raros). Archivos `scripts/<id>.sim`; se invocan con
`{"type": "script", "script": "<id>", "args": {...}, "contract": {"max_damage": 400}}`. Importar **nunca ejecuta** el script (solo lo compila). Un script
**sin `contract`** que haga daño/curación no es valorable y **no entra en modo reglamentado**; un error en un script de efecto **aborta el combate**.
Especificación completa: `docs/SCRIPTING_API.md`; ejemplo: `content/packages/rune_caster`.

## 11. Presupuesto y equilibrio (provisional)

- **Cada personaje tiene un coste de creación (PC)** calculado automáticamente con un perfil externo. El perfil por defecto es **ILUSTRATIVO** (cifras de prueba,
  no definitivas): `builtin/reference_costs`. Presupuestos de ejemplo: `small 500, standard 1000, large 2000, epic 5000`.
- **Modo libre** (por defecto): sin límite; solo avisa. **Modo reglamentado**: exige estar dentro del presupuesto y que todo sea evaluable.
- **Igualdad de PC no implica igualdad de poder.** El criterio de equilibrio práctico es el **resultado en duelos**: apunta a **35–65 % de victorias** contra el
  conjunto de oponentes de serie y duelos de 6–30 turnos. Usa `tools/character_check.gd` (§12) y ajusta.
- Referencia medida (motor 0.5.0, perfil ilustrativo, 10 duelos × 8 rivales, el personaje como equipo A, semilla 1) con las plantillas de `content/templates/`:

| Plantilla | Coste (PC) | % victorias | Lectura |
|---|---:|---:|---|
| `character_minimal` | 21 | 19 % | base sin habilidades: débil a propósito |
| `character_summoner` | 90 | 51 % | equilibrado |
| `character_with_libraries` | 158 | 100 % | **demasiado fuerte** para su coste: ejemplo de lo que hay que recortar |
| `character_tank_ai` | 253 | 76 % | fuerte y lento (duelos largos) |
| `character_caster` | 390 | 31 % | algo débil |
| `character_status_user` | 466 | 69 % | fuerte |

Los costes **no** están calibrados con contenido real: no presumas que más PC = más fuerte. Un calibrador empírico existe (`docs/BALANCE_RULES.md` §6).

## 12. Flujo de trabajo OBLIGATORIO (ciclo de retroalimentación)

1. Crea la carpeta del paquete con los JSON.
2. **Valida y prueba** (no modifica nada del usuario; usa una biblioteca temporal con ejemplos y plantillas):
   ```bash
   godot --headless --path . --script res://tools/character_check.gd -- ruta/mi_personaje --reps 10 --seed 1
   ```
   Opciones: `--deps ruta` (otro paquete tuyo del que dependes, importado antes), `--vs pkg:examples/iron_vanguard` (oponentes concretos),
   `--budget standard|small|large|epic`, `--json` (salida para máquinas). Código de salida 0 = válido, 2 = rechazado.
3. Si sale **RECHAZADO**, lee cada error (`archivo: [código] ruta: mensaje`) y corrígelo (§13). Vuelve al paso 2 hasta que pase.
4. Lee el **Diagnóstico**: habilidades nunca usadas, % de victorias, duelos muy cortos/largos, empates, presupuesto. Ajusta números o la IA y repite.
5. Duelo con registro para entender un caso concreto:
   ```bash
   godot --headless --path . --script res://tools/package_tool.gd -- import ruta/mi_personaje
   godot --headless --path . --script res://tools/run_duel.gd -- pkg:mi_espacio/mi_heroe pkg:examples/iron_vanguard 42 --log
   ```
6. Entrega el paquete final con la salida de `character_check` que lo respalda (resumen de coste y % de victorias).

## 13. Errores frecuentes y cómo corregirlos

| Mensaje (resumen) | Causa | Arreglo |
|---|---|---|
| `propiedad desconocida 'abilities'` en `character.json` | habilidades en el archivo equivocado | muévelas a `abilities.json` |
| `propiedad desconocida 'X'` (en general) | campo inventado | usa solo los campos de esta guía; el error lista los permitidos |
| `schema ... debe valer 'simhalla.<tipo>/1'` | falta o está mal `schema` | pon el valor exacto de cada archivo |
| `ia: usa la habilidad inexistente 'x'` | la IA cita una habilidad que no existe | créala en `abilities.json` o corrige el id |
| `summon.lifespan: unit no admitida` | unidad de duración incorrecta | `target_turns`, `global_actions`, `time` o `permanent` |
| `dependencia '...' no encontrada` | `imports`/`ai_ref` sin declarar/importar | añádela a `manifest.dependencies` y pásala con `--deps` |
| `[version_conflicto]` | mismo `id@version` con otro contenido | sube `version` |
| `formula ... invalida` | variable o función inventada, división por cero | revisa §6 |
| `elemento 'x' no está en el catálogo` | elemento fuera de la lista | usa `fire, water, earth, air, lightning, ice, light, dark` |
| `[equilibrio]` (modo reglamentado) | fuera de presupuesto o no evaluable | baja stats/habilidades; evita scripts sin `contract` |
| `[codificacion]` | BOM o no UTF-8 | guarda UTF-8 sin BOM |
| habilidad «NO se usó» (diagnóstico) | la IA no la elige: recurso insuficiente, `requires`, regla ausente o mal ordenada | añade/ordena la regla, sube el recurso o su regeneración |
| duelo «ABORTADO» | fórmula/script con error en tiempo de ejecución | reproduce con `run_duel.gd --log` y corrige la fórmula |

## 14. Recetas (plantillas validadas en `content/templates/`)

Copia la plantilla más cercana, cambia `id`/`name`/números y repite el ciclo de §12.

| Plantilla | Enseña |
|---|---|
| `character_minimal` | lo mínimo válido (solo stats) |
| `character_caster` | recurso + habilidades con coste/cooldown + curación + IA con condiciones |
| `character_tank_ai` | pasiva, reacción por evento, estado propio, IA `scored` con pesos |
| `character_summoner` | `summons.json`, invocar, veneno nativo, IA con `ally.alive_count` y `target.status` |
| `character_status_user` | estado propio con daño periódico y modificadores, IA `state_machine` |
| `library_abilities` + `library_ai` + `character_with_libraries` | bibliotecas reutilizables, `imports`, `ai_ref`, dependencias |

Ejemplos mayores: `content/packages/arcane_duelist` (artefacto + dependencias), `rune_caster` (SimScript), `iron_vanguard`, `ai_profiles`.

## 15. Lista de comprobación antes de entregar

- [ ] `character_check` termina **sin errores** (código 0) y sin `ERROR TECNICO`.
- [ ] Todos los JSON: UTF-8, sin comentarios ni comas finales, con su `schema` exacto.
- [ ] Ids en minúsculas con `_`; `manifest.id` con `espacio/nombre`; `version` semver.
- [ ] Toda habilidad usada por la IA existe; la IA termina en `basic_attack`; las `reaction`/`passive` no están en la IA.
- [ ] Todo recurso gastado existe en `resources.json` y tiene regeneración razonable.
- [ ] Todo estado usado es nativo o está definido en `effects.json`; todo elemento está en el catálogo.
- [ ] Ninguna habilidad queda sin usar (o es una reacción/pasiva intencionada).
- [ ] Resultado orientativo: 35–65 % de victorias, duelos de 6–30 turnos; si no, justifícalo o ajusta.
- [ ] Sin SimScript salvo necesidad real (y con `contract` si hace daño/curación).

## 16. Referencias (solo si necesitas más detalle)

`docs/PACKAGES.md` (formato y versiones) · `docs/ABILITY_REFERENCE.md` (efectos, estados, invocaciones) · `docs/AI_REFERENCE.md` (IA completa) ·
`docs/EVENTS.md` (eventos y condiciones) · `docs/COMBAT_RULES.md` (reglas del motor) · `docs/BALANCE_RULES.md` (costes y calibración) ·
`docs/SCRIPTING_API.md` (SimScript) · `schemas/*.schema.json` (esquemas públicos, fuente de verdad de los campos permitidos).
