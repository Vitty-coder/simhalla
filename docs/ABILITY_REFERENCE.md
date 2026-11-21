# ABILITY_REFERENCE — Habilidades, efectos y estados (fases 1–3)

> Solo lo **realmente implementado**. Lo que no figura aquí no existe: los campos
> desconocidos se rechazan. Esquemas públicos: `schemas/common.schema.json`
> (`ability`, `effect`, `status`, `summon_template`). Eventos y condiciones: `EVENTS.md`.
> Reglas de resolución y convenciones de tiempo: `COMBAT_RULES.md`.

## 1. Habilidad

```json
{"id": "fireball", "name": "Bola de fuego", "action_type": "main|free|reaction", "targeting": "enemy|ally|self|any",
 "target_count": 1, "cost": {"mana": 20}, "tags": ["spell"], "effects": [ ... ],
 "cooldown": 3, "uses_per_combat": 2, "uses_per_turn": 1,
 "charges": {"max": 3, "initial": 3, "recharge": {"unit": "target_turns", "amount": 2}},
 "requires": {"self.hp_ratio": {"lt": 0.5}, "target.status.stun": {"ge": 1}},
 "trigger": {"event": "damage_dealt", "when": {...}, "target": "event_source", "chance": 0.5, "while_dead": false, "limit_per_turn": 1},
 "passive": {"modifiers": [{"stat": "DEF", "kind": "flat", "value": 20}]},
 "cast_time": 8, "interruptible": true, "ignore_taunt": false}
```
| Campo | Significado |
|---|---|
| `action_type` | `main` (1 por turno), `free` (sin cuota universal; limítela con usos/cooldown), `reaction` (fuera del turno propio, vía `trigger`) |
| `cost` | recursos; se pagan **al comprometer** la acción |
| `cooldown` | número (turnos del dueño, decrece al **inicio** de su turno) u objeto duración (`target_turns`, `global_actions`, `time`, `events`) |
| `uses_per_combat` / `uses_per_turn` | límites de uso (por turno **global**) |
| `charges` | cargas con recarga (`target_turns`, `global_actions` o `time`) |
| `requires` | condiciones (ver `EVENTS.md`): `self.*` y `target.*` (el objetivo no válido no es elegible) |
| `trigger` | convierte la habilidad en **disparada** (reacción/automática): NO la elige la IA. `target` por defecto: `self` si `targeting` es `self`, si no `event_source`. Conjunto de `target`: `self, event_source, event_target, lowest_hp_enemy, first_enemy` |
| `passive` | modificadores permanentes mientras se posea la habilidad |
| `cast_time` | habilidad **canalizada/cargada**: efectos tras `cast_time` u.t.; mientras canaliza no gana iniciativa; el turno termina al empezar |
| `ignore_taunt` | ignora la provocación |

**Categorías (PROJECT.md 6.1) y cómo se expresan:** activa = habilidad normal; pasiva = `passive` y/o `trigger`; reactiva = `action_type: reaction` + `trigger`; automática = `trigger` sobre `turn_started`/`combat_started`/…; canalizada y cargada = `cast_time` (la carga cuesta al comprometer); sostenida = estado con `periodic` que gasta recurso + `trigger` sobre `resource_limit`; alternable = dos habilidades con `requires` sobre `self.status.<id>` (patrones verificados en las pruebas); transformación = estado con bloque `form`.

## 2. Operaciones de efecto

Comunes a todas: `"on"` (a quién se aplica: `targets` [defecto], `caster`, `all_enemies`, `all_allies` [sin el lanzador], `random_enemy`, `random_ally`, `lowest_hp_enemy`; orden por `slot`, azar solo del flujo `select`, reproducible) y `"chance": 0..1` (**una tirada por objetivo**, flujo `proc`, evento `proc` trazado).

| `type` | Campos | Notas |
|---|---|---|
| `damage` | `components[]` (`damage_type`, `element`, `formula`, `pen_flat`, `pen_pct`, `elem_pen`), `always_hit`, `can_crit`, `crit_bonus` | ver COMBAT_RULES §5 |
| `heal` | `formula`, `can_crit` | `× HEAL_REC`, overheal |
| `apply_status` | `status`, `stacks`, `duration`, `magnitude` (número o fórmula) | el estado debe existir (nativo o propio) |
| `remove_status` | `status` \| `tags[]` \| `beneficial`, `count`, `force` | respeta `dispellable` salvo `force` |
| `extend_status` | `status` \| `tags[]`, `amount` (±) | alarga/acorta la duración restante; ≤ 0 lo expira |
| `invert_status` | `status` \| `tags[]` \| `beneficial`, `count` | invierte modificadores (flat/pct_add se niegan, mult se invierte) y periódicos (daño ↔ curación); repetir lo deshace; cuenta como beneficioso al revés |
| `propagate_status` | `status` \| `tags[]`, `to: target_allies|target_enemies|caster_allies|caster_enemies|all_others|random_other`, `count` | copia el estado (pilas, magnitud, duración restante, origen) a otras entidades; en `on_expire`/`on_death` de un estado lo extiende al expirar/morir |
| `transfer_status` | `mode: steal|copy|give`, filtro, `count` | conserva pilas, magnitud y duración restante |
| `modify_resource` | `resource`, `amount`, `mode: add|set`, `property: value|max` | emite `resource_limit` al tocar límites |
| `modify_initiative` | `mode: add|set|steal|extra_turn`, `amount` (unidades) | nunca < 0; `extra_turn` = +umbral |
| `modify_cooldown` | `ability` (opc.), `mode: reduce|add|reset`, `amount` | |
| `summon` | `template`, `count` (1–8), `lifespan`, `inherit.stat_pct` | plantilla en `summons` del PJ |
| `record_state` / `restore_state` | `key`, `what: [hp,resources,statuses]`, `consume` | restauración selectiva; con `statuses` se restaura el **conjunto** de estados (retira los actuales, incluso no disipables, y reaplica los grabados con su duración restante e inversión); consumible; no revive ni rebobina RNG |
| `delayed_effect` | `delay` (u.t.), `effects[]` | daño retrasado / liberar efectos almacenados; sin anidar |
| `repeat_action` | `times` (1–3) | repite la acción anterior **gratis** |
| `copy_action` | — | usa la última habilidad del objetivo **gratis** |
| `emit_event` | `name`, `data{}` | emite `user.<name>` (disparable) |
| `metric` | `name`, `amount` | métrica personalizada → `CombatResult.metrics` |

Fórmulas: igual que en fase 1 más `status.stacks|magnitude|shield` dentro de estados. Orígenes permitidos: `caster`, `target`, `status`.

## 3. Estados (`statuses` del PJ / `effects.json`)

```json
{"id": "poison", "name": "Veneno", "tags": ["dot"], "beneficial": false, "dispellable": true, "group": "",
 "stacking": {"policy": "stack_intensity", "max_stacks": 5},
 "duration": 4,
 "modifiers": [{"stat": "ATK", "kind": "pct_add", "value": -0.1, "per_stack": true}],
 "flags": {"skip_turn": false, "suspend_initiative": false, "interrupt_channel": false, "taunt": false,
           "block_tags": ["spell"], "block_action_types": ["free"], "immune_status_tags": ["cc"],
           "suspend_statuses": ["buff"], "suspend_cooldowns": false},
 "defense": {"immune_damage_types": [], "immune_elements": [], "absorb_elements": [],
             "absorb": {"amount": "100", "damage_types": [], "elements": []},
             "reduction": {"flat": 0, "pct": 0.2, "damage_types": []}, "block": {"chance": 0.3, "pct": 0.5},
             "parry": {"chance": 0.1}, "reflect": {"pct": 0.25}, "prevent_death": {"survive_hp": 1}},
 "periodic": [{"on": "turn_start|turn_end", "effects": [ ... ]}],
 "on_apply": [ ... ], "on_expire": [ ... ], "on_death": [ ... ],
 "form": {"add_abilities": [ ... ], "remove_abilities": ["id"], "ai": {"type": "priority_list", "rules": [...]}}}
```
- **Duración** (`duration`): número = turnos del afectado; u objeto `{unit: target_turns|caster_turns|global_actions|time|events|permanent, amount, event, filter}`. Convención: los estados decrementan **al final** del turno correspondiente y el turno en que se aplicaron **no cuenta**.
- **Políticas** (`stacking.policy`): `stack_intensity` (+1 pila, reinicia duración), `stack_duration` (suma duración), `independent` (instancias separadas hasta `max_stacks`), `refresh`, `replace`, `keep_strongest` (por magnitud×pilas), `ignore`. `group`: un estado nuevo sustituye a los del mismo grupo.
- **Modificadores** escalan con las pilas (`per_stack`, por defecto sí): `flat`/`pct_add` × pilas, `mult` ^ pilas.
- **Defensas** (solo existen si un estado las concede): orden inmunidad → absorción elemental (→ curación) → parada → bloqueo → reducción (% y luego plana) → escudo. `reflect` devuelve daño verdadero (no se vuelve a reflejar). `prevent_death` se consume.
- **Suspender efectos y cooldowns:** `flags.suspend_statuses` (etiquetas, o `["*"]` para todos los demás estados) deja **suspendidos** los estados del afectado con esas etiquetas: sin modificadores, banderas, defensas, periódicos ni cuenta atrás (las duraciones por tiempo se pausan y se rearman). `flags.suspend_cooldowns` detiene el avance de los cooldowns y recargas por turnos/acciones (los cooldowns por tiempo no se pausan). Eventos `status_changed` con `change: suspended|resumed`.
- **Invertir:** `invert_status` (ver §2); la inversión no afecta a `defense` ni `flags`.
- **`on_death`:** efectos que se ejecutan al morir el afectado, antes de retirar sus estados (p. ej. propagarlo).
- **Formas**: `form` añade/quita habilidades y sustituye la IA mientras dure el estado; los modificadores del estado cambian estadísticas, afinidades y resistencias; al terminar (expiración, disipación, muerte) todo se restaura. Un `group` común hace las formas excluyentes.
- **Nativos como datos** (`content/statuses/native_statuses.json`, valores ilustrativos): `poison, burn, bleed, stun, silence, freeze, regen, taunt`. Un PJ puede definir los suyos; redefinir un id con contenido distinto es error (idéntico se acepta).

## 4. Invocaciones (`summons`)

```json
"summons": {"wolf": {"name": "Lobo", "stats": {"HP": 200, "ATK": 60, "SPD": 120}, "basic_attack": true,
                       "abilities": [ ... ], "ai": {...}, "resources": {...}, "statuses": [ ... ], "counts_for_victory": false}}
```
Entidades completas (ATB, HP, habilidades, recursos e IA propios). Equipo del invocador; `counts_for_victory` falso por defecto. Límites: `summons.max_per_owner` (8), `summons.max_entities` (64), profundidad 3. `summons.on_owner_death`: `despawn` (defecto) o `stay`. Las plantillas se validan como entidades al cargar el PJ y las referencias, al montar el combate.

## 5. Límites técnicos (no desactivables por contenido)
`safety.max_events`, `max_event_depth`, `max_reaction_chain` (4; techo 8), `max_scheduled` (1000; techo 10 000), entidades ≤ 256, profundidad de repetición/copia 3, 8 niveles de efectos periódicos anidados, ≤ 64 métricas distintas. Al alcanzar uno se emite `limit_reached` y se continúa; el contenido no puede abortar el combate por esto.

## 6. Artefacto (único, opcional) — `artifact.json` o `artifact` del PJ
Mismas herramientas que un PJ/habilidad: `modifiers` (con origen `artifact:<id>`), `abilities` (incluidas pasivas, disparadores, estados y cooldowns), `resources`, `statuses` (propios), `summons` y `ai_rules` (reglas de IA **antepuestas** a las del personaje; funcionan con `priority_list`, `scored`, `state_machine` y `behavior_tree`, no con `passive`). Conflictos (recurso o plantilla repetidos, estado redefinido con otro contenido) son error; un estado idéntico se admite.

## 7. Catálogo elemental
`elements` del reglamento (por defecto fire, water, earth, air, lightning, ice, light, dark; ampliable o vacío). Todo elemento usado por contenido (componentes de daño, `ELEM_AFF.*`/`ELEM_RES.*`, pasivas, estados, invocaciones) debe existir en él: el montaje del combate (y la importación) lo valida. Los estados nativos ilustrativos no se validan contra el catálogo.

## 8. Reservar acciones y reacciones (patrón)
"Reservar" = preparar y liberar una sola vez: una habilidad aplica un estado de preparación y una reacción con `requires: {"self.status.<prep>": {"ge": 1}}` se dispara y retira el estado (`remove_status` con `on: caster`). Verificado en las pruebas. La decisión de *cuándo* reservar es de la IA (fase 4).

## 8b. Operación `script` (fase 5)
`{"type": "script", "script": "<id>", "args": {…}}`: ejecuta `fn run(ctx)` de `scripts/<id>.sim` (o de `scripts` de la entidad) una vez por acción. Sus cambios pasan por el motor (eventos, interceptores). `contract` opcional: topes verificables que permiten valorarlo (fase 6). Ver `SCRIPTING_API.md` y `BALANCE_RULES.md`.

## 9. No implementado todavía (fases posteriores)
Costes de creación (fase 6). La lógica personalizada está en `SCRIPTING_API.md` (operación `script`).
