class_name EventLog
extends RefCounted
## Registro append-only de eventos con huella SHA-256 incremental.
##
## La huella se calcula SIEMPRE, independientemente del nivel de traza, de modo
## que dos ejecuciones con distinta traza son comparables (paridad exigida).

enum TraceLevel { FULL, REDUCED }

var level: TraceLevel = TraceLevel.FULL
var events: Array[Dictionary] = [] ## solo con TraceLevel.FULL
var count: int = 0
var counts_by_type: Dictionary = {}
var _hash := HashingContext.new()
var _digest: String = ""


func _init(trace_level: TraceLevel = TraceLevel.FULL) -> void:
	level = trace_level
	_hash.start(HashingContext.HASH_SHA256)


func record(ev: CombatEvent) -> void:
	var d := ev.to_dict()
	count += 1
	counts_by_type[ev.type] = int(counts_by_type.get(ev.type, 0)) + 1
	if _digest == "":
		_hash.update((JSON.stringify(d, "", true, true) + "\n").to_utf8_buffer())
	if level == TraceLevel.FULL:
		d["data"] = ev.data.duplicate(true) # el registro no comparte estado con el evento vivo
		events.append(d)


## Cierra el hash (idempotente). Tras llamarlo no se aceptan mas eventos en la huella.
func digest() -> String:
	if _digest == "":
		_digest = _hash.finish().hex_encode()
	return _digest


func of_type(type: String) -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for e in events:
		if e["type"] == type:
			out.append(e)
	return out
