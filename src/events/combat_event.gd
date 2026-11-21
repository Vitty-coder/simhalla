class_name CombatEvent
extends RefCounted
## Evento tipado del combate.
##
## Un evento se REGISTRA inmutablemente en el momento de emitirse (id
## monotono). Si es de fase PRE, los interceptores pueden modificar `data` o
## cancelarlo mientras esta pendiente; cada cambio genera ademas un evento
## EVENT_MODIFIED / EVENT_CANCELLED trazable (nunca se reescribe el registro).

enum Phase { INFO, PRE, POST }

var id: int = 0
var type: String = ""
var time: int = 0 ## microunidades de tiempo virtual
var phase: Phase = Phase.INFO
var source_id: String = ""
var target_id: String = ""
var cause_id: int = 0 ## 0 = sin causa (raiz)
var data: Dictionary = {}

# Estado vivo mientras es PRE (no forma parte del registro inmutable)
var cancelled: bool = false
var cancel_reason: String = ""
var cancelled_by: String = ""
var modifications: Array = []


func cancel(by: String, reason: String = "") -> void:
	if phase != Phase.PRE:
		return
	cancelled = true
	cancelled_by = by
	cancel_reason = reason


## Modifica un dato de un evento PRE pendiente; queda anotado.
func set_data(key: String, value: Variant, by: String) -> void:
	if phase != Phase.PRE:
		return
	modifications.append({"key": key, "old": data.get(key), "new": value, "by": by})
	data[key] = value


func phase_name() -> String:
	return Phase.keys()[phase].to_lower()


## Representacion inmutable para registro, hash e informes.
func to_dict() -> Dictionary:
	return {
		"id": id, "type": type, "time": time, "phase": phase_name(),
		"source": source_id, "target": target_id, "cause": cause_id, "data": data,
	}
