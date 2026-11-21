class_name StatusInstance
extends RefCounted
## Instancia en ejecucion de un estado sobre una entidad.

var def: StatusDef = null
var holder_id: String = ""
var source_id: String = ""
var seq: int = 0
var stacks: int = 1
var magnitude: float = 1.0 ## intensidad (p. ej. potencia del veneno); usable en formulas como status.magnitude
var duration: Duration = null
var applied_cause: int = 0
var applied_turn: int = 0
var shield: float = 0.0 ## reserva restante de la absorcion (defense.absorb)
var modifier_source: String = "" ## origen de sus StatModifier (para retirarlos en bloque)
var timer_seq: int = -1 ## evento temporizado de caducidad (duracion por tiempo)
var form_applied: Dictionary = {} ## estado previo guardado al aplicar una forma
var inverted: bool = false ## efectos invertidos (invert_status): modificadores y periodicos al reves
var frozen: bool = false ## suspendido por otro estado (suspend_statuses): sin modificadores, banderas, defensas, periodicos ni cuenta atras
var frozen_time_left: int = -1 ## microunidades restantes de una duracion por tiempo mientras esta suspendido


func strength() -> float:
	return magnitude * float(stacks)


func to_dict() -> Dictionary:
	return {
		"id": def.id, "seq": seq, "stacks": stacks, "magnitude": magnitude, "source": source_id,
		"duration": duration.to_dict() if duration != null else {}, "shield": shield,
		"inverted": inverted, "frozen": frozen,
	}
