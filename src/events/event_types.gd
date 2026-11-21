class_name EventTypes
extends RefCounted
## Catalogo de tipos de evento (familias del PROJECT.md seccion 6.4).
## Fase 1 implementa las marcadas con (1); el resto queda reservado.

# Ciclo de combate y tiempo
const COMBAT_STARTED := "combat_started" # (1)
const COMBAT_ENDED := "combat_ended" # (1)
const TIME_ADVANCED := "time_advanced" # (1)
const TIMED_EVENT := "timed_event" # (1)
const LIMIT_REACHED := "limit_reached" # (1)
const ERROR := "error" # (1)

# Turnos y acciones
const TURN_STARTED := "turn_started" # (1) PRE: cancelar = turno omitido
const TURN_SKIPPED := "turn_skipped" # (1)
const TURN_ENDED := "turn_ended" # (1)
const ACTION_SELECTED := "action_selected" # (1) decision de la IA
const ACTION_REJECTED := "action_rejected" # (1)
const ACTION_STARTED := "action_started" # (1) PRE: cancelar = interrumpir
const ACTION_INTERRUPTED := "action_interrupted" # (1)
const ACTION_RESOLVED := "action_resolved" # (1)
const WAIT := "wait" # (1)
const AI_FALLBACK := "ai_fallback" # (1)
const TARGET_SKIPPED := "target_skipped" # (1)

# Impacto
const HIT := "hit" # (1)
const MISS := "miss" # (1)
const CRIT := "crit" # (1)

# Dano, curacion, recursos, vida
const DAMAGE_PRE := "damage_pre" # (1) PRE: modificable/cancelable
const DAMAGE_DEALT := "damage_dealt" # (1)
const HEAL_PRE := "heal_pre" # (1) PRE
const HEAL_DONE := "heal_done" # (1)
const HP_CHANGED := "hp_changed" # (1)
const RESOURCE_CHANGED := "resource_changed" # (1)

# Muerte
const DEATH_PRE := "death_pre" # (1) PRE: cancelar = prevencion de muerte
const DEATH := "death" # (1)

# Trazabilidad de intercepciones
const EVENT_MODIFIED := "event_modified" # (1)
const EVENT_CANCELLED := "event_cancelled" # (1)

# Fase 3: estados, reacciones, canalizacion, iniciativa, invocaciones, formas, temporalidad
const PROC := "proc" # tirada de probabilidad de un efecto/reaccion
const STATUS_APPLIED := "status_applied" # PRE: cancelar = aplicacion bloqueada
const STATUS_GAINED := "status_gained" # POST: tras aplicarse (y ejecutar on_apply); reaccionar a esto, no a status_applied
const STATUS_REJECTED := "status_rejected"
const STATUS_CHANGED := "status_changed" # pilas/duracion/intensidad
const STATUS_REMOVED := "status_removed"
const STATUS_EXPIRED := "status_expired"
const REACTION_TRIGGERED := "reaction_triggered"
const REACTION_DECLINED := "reaction_declined" # la IA declino una reaccion elegible (fase 4)
const CHANNEL_STARTED := "channel_started"
const CHANNEL_COMPLETED := "channel_completed"
const CHANNEL_INTERRUPTED := "channel_interrupted"
const INITIATIVE_CHANGED := "initiative_changed"
const RESOURCE_LIMIT := "resource_limit"
const SUMMON_CREATED := "summon_created"
const ENTITY_DESPAWNED := "entity_despawned"
const TRANSFORMED := "transformed"
const REVERTED := "reverted"
const STATE_RECORDED := "state_recorded"
const STATE_RESTORED := "state_restored"
const DELAYED_SCHEDULED := "delayed_scheduled"
const DELAYED_RELEASED := "delayed_released"
const STAT_CHANGED := "stat_changed"
const RESURRECTED := "resurrected"
const USER_EVENT := "user_event"
const SCRIPT_RUN := "script_run" # una ejecucion de script de efecto (fase 5): instrucciones, llamadas, operaciones
