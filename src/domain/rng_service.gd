class_name RngService
extends RefCounted
## Flujos de azar con nombre derivados de una semilla maestra.
##
## Cada flujo ("hit", "crit", "tiebreak", ...) es independiente: consumir
## tiradas en uno no desplaza la secuencia de los demas. Todo el azar del
## combate debe salir de aqui (nunca de randf()/randi() de Godot).

var master_seed: int = 0
var _streams: Dictionary = {}


func _init(seed_value: int = 0) -> void:
	master_seed = seed_value


func stream(name: String) -> Rng:
	if not _streams.has(name):
		_streams[name] = Rng.new(Rng.mix(master_seed ^ Rng.fnv1a64(name)))
	return _streams[name]


## Estado de todos los flujos creados (para snapshots/depuracion).
func get_states() -> Dictionary:
	var out := {}
	var names: Array = _streams.keys()
	names.sort()
	for n in names:
		out[n] = (_streams[n] as Rng).state
	return out
