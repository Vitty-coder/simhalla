class_name TurnState
extends RefCounted
## Estado del turno en curso: presupuesto de acciones de la entidad activa.

var entity: CombatEntity = null
var number: int = 0
var main_used: int = 0
var free_used: int = 0
var actions_taken: int = 0
var start_event_id: int = 0


func _init(e: CombatEntity = null, n: int = 0) -> void:
	entity = e
	number = n


## Consume el hueco de accion correspondiente (un intento cuenta aunque se interrumpa).
func consume(ability: AbilityDef) -> void:
	match ability.action_type:
		AbilityDef.ActionType.MAIN:
			main_used += 1
		AbilityDef.ActionType.FREE:
			free_used += 1
