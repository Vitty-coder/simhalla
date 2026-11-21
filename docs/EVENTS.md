# EVENTS — Catálogo de eventos y condiciones (fases 1–3)

Cada evento: `id` (monótono), `type`, `time` (microunidades), `phase` (`info|pre|post`), `source`, `target`, `cause` (id del evento que lo originó, 0 = raíz), `data`. Los eventos `pre` son interceptables (modificar/cancelar → `event_modified`/`event_cancelled` trazables); los observadores y los `trigger` reciben el estado final; un `pre` **cancelado no dispara reacciones**.

| Familia | Eventos |
|---|---|
| Combate/tiempo | `combat_started`, `combat_ended`, `time_advanced`, `timed_event`, `limit_reached`, `error` |
| Turnos/acciones | `turn_started` (pre), `turn_skipped`, `turn_ended`, `action_selected`, `action_rejected`, `action_started` (pre), `action_interrupted`, `action_resolved`, `wait`, `ai_fallback`, `target_skipped`, `reaction_triggered`, `reaction_declined` (la IA declinó una reacción elegible; `data.reason`), `script_run` (ejecución de un script de efecto: `script`, `hash`, `ok`, `instructions`, `api_calls`, `mutations`), `proc` |
| Impacto/daño/curación | `hit`, `miss`, `crit`, `damage_pre` (pre), `damage_dealt`, `heal_pre` (pre), `heal_done`, `hp_changed` |
| Recursos/iniciativa | `resource_changed`, `resource_limit` (`limit: min|max`), `initiative_changed` |
| Muerte | `death_pre` (pre), `death`, `entity_despawned` |
| Estados | `status_applied` (pre, antes de existir), **`status_gained`** (post, tras aplicarse: reaccione a este), `status_changed` (`change`: stack_intensity, refresh, duration, inverted, restored, suspended, resumed, o cooldown), `status_rejected`, `status_removed`, `status_expired` |
| Canalización | `channel_started`, `channel_completed`, `channel_interrupted` |
| Invocaciones/formas | `summon_created`, `transformed`, `reverted` |
| Temporalidad | `state_recorded`, `state_restored`, `delayed_scheduled`, `delayed_released` |
| Usuario | `user.<name>` (`emit_event`) |
| Trazabilidad | `event_modified`, `event_cancelled` |

Orden notable: `damage_pre` → `damage_dealt` → `hp_changed` → `death_pre`/`death`. La vida **ya está aplicada** cuando se notifica `damage_dealt` (D-043).

## Condiciones (`requires`, `trigger.when`)
`{"<scope>.<campo>": {"<op>": valor}}`, todas deben cumplirse; si el valor no existe la condición falla.
- `scope`: `self`, `target` (restricciones: el objetivo evaluado), `event` (solo en `trigger.when`).
- Campos de entidad: `hp`, `hp_max`, `hp_ratio`, `res.<recurso>`, `status.<id>` (pilas), `tag.<etiqueta>` (1/0).
- Campos de evento: `type`; `source`/`target` como relación respecto a `self` (`"self"|"ally"|"enemy"`); y **cualquier clave de `data`** (`amount`, `applied`, `crit`, `element`, `damage_type`, `ability`, `status`, `resource`, `limit`, …; los booleanos se comparan como 1/0 con `eq`… o `{"eq": true}`).
- Operadores: `lt le gt ge eq ne`; valores: número, texto o booleano.
