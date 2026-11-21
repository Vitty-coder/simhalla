class_name StatModifier
extends RefCounted
## Modificador de una estadistica con origen y prioridad identificables.
##
## Tipos soportados en la fase 1. Conversiones entre estadisticas y formulas
## dinamicas (p. ej. ATK segun HP perdido) llegan con la fase 3 (efectos) sin
## cambiar el contrato de StatSet: aniadiran nuevos `Kind`.

enum Kind {
	SET, ## Sustituye el valor base (gana mayor prioridad; empate: el mas reciente).
	FLAT, ## Suma plana.
	PCT_ADD, ## Porcentaje aditivo (0.25 = +25 %); se suman entre si.
	MULT, ## Multiplicador; se multiplican entre si.
	MIN, ## Suelo del valor final (gana el mayor).
	MAX, ## Techo del valor final (gana el menor; prevalece sobre MIN).
}

var id: String = ""
var stat: String = ""
var kind: Kind = Kind.FLAT
var value: float = 0.0
var source_id: String = ""
var priority: int = 0
var seq: int = 0 ## Asignado por StatSet; orden estable de insercion.


static func make(stat_id: String, kind_: Kind, value_: float, source: String = "", prio: int = 0, mod_id: String = "") -> StatModifier:
	var m := StatModifier.new()
	m.stat = stat_id
	m.kind = kind_
	m.value = value_
	m.source_id = source
	m.priority = prio
	m.id = mod_id
	return m


func to_dict() -> Dictionary:
	return {
		"id": id, "stat": stat, "kind": Kind.keys()[kind], "value": value,
		"source": source_id, "priority": priority,
	}
