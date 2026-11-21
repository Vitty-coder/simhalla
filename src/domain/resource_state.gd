class_name ResourceState
extends RefCounted
## Recurso opcional y configurable de una entidad (mana, furia, cargas, ...).
## Unicos recursos obligatorios del motor: vida e iniciativa (viven en la entidad).
## Regeneracion, eventos de limite y modificacion en combate: fase 3.

var id: String = ""
var value: float = 0.0
var initial: float = 0.0
var min_value: float = 0.0
var max_value: float = INF
var regen_per_turn: float = 0.0 ## se aplica al inicio del turno del dueno


static func from_dict(res_id: String, d: Dictionary) -> ResourceState:
	var r := ResourceState.new()
	r.id = res_id
	r.min_value = float(d.get("min", 0.0))
	r.max_value = float(d.get("max", 1.0e18)) if d.has("max") else 1.0e18
	r.initial = float(d.get("initial", r.max_value if d.has("max") else 0.0))
	r.value = clampf(r.initial, r.min_value, r.max_value)
	r.regen_per_turn = float(d.get("regen_per_turn", 0.0))
	return r


func change(delta: float) -> float:
	var old := value
	value = clampf(value + delta, min_value, max_value)
	return value - old


func to_dict() -> Dictionary:
	return {"id": id, "value": value, "min": min_value, "max": max_value}
