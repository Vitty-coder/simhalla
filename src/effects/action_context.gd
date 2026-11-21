class_name ActionContext
extends RefCounted
## Contexto de resolucion de una accion (lo que ven las operaciones).

var engine: CombatEngine = null
var actor: CombatEntity = null
var ability: AbilityDef = null
var targets: Array[CombatEntity] = []
var cause_id: int = 0 ## id del evento que origina la accion
var rolls: Dictionary = {} ## objetivo -> {"hit": bool, "crit": bool} (roll_scope=per_action)
var status: StatusInstance = null ## estado que origina la resolucion (periodicos, on_apply/on_expire)
var caster_override: CombatEntity = null
