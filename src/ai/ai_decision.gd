class_name AIDecision
extends RefCounted
## Propuesta de la IA. La IA nunca altera el combate: el motor la revalida.

enum Kind { ABILITY, WAIT }

var kind: Kind = Kind.WAIT
var ability_id: String = ""
var target_ids: Array[String] = []
var reason: String = "" ## regla/motivo (trazabilidad)
var details: Dictionary = {} ## candidatos, puntuaciones, descartes...
## Operaciones de memoria propuestas: {op:"set"|"incr", key, value} | {op:"state", value}.
## La IA no escribe su memoria: el motor las aplica (AIMemory.apply_ops).
var memory_ops: Array = []
## Si no esta vacio, el motor emite `ai_fallback` con este motivo (la IA fallo y espera).
var fallback: String = ""


static func use(ability: String, targets: Array, why: String = "", extra: Dictionary = {}) -> AIDecision:
	var d := AIDecision.new()
	d.kind = Kind.ABILITY
	d.ability_id = ability
	for t in targets:
		d.target_ids.append(str(t))
	d.reason = why
	d.details = extra
	return d


static func wait(why: String = "", extra: Dictionary = {}) -> AIDecision:
	var d := AIDecision.new()
	d.kind = Kind.WAIT
	d.reason = why
	d.details = extra
	return d


func to_dict() -> Dictionary:
	var d := {
		"kind": Kind.keys()[kind].to_lower(), "ability": ability_id,
		"targets": target_ids, "reason": reason, "details": details,
	}
	if not memory_ops.is_empty():
		d["memory_ops"] = memory_ops
	return d
