class_name EventDispatcher
extends RefCounted
## Suscripciones a eventos: interceptores (pre-resolucion) y observadores.
##
## - Interceptor: Callable(event: CombatEvent, engine: CombatEngine). Solo se
##   invoca para eventos PRE. Puede llamar event.set_data(...) o event.cancel(...).
## - Observador: Callable(event: CombatEvent, engine: CombatEngine). Notificacion
##   posterior al registro y a la intercepcion; no puede alterar el evento.
## Orden estable: prioridad ascendente (menor primero) y luego orden de alta.
## El tipo "*" suscribe a todos los eventos.

var _interceptors: Dictionary = {} ## type -> Array[{prio, seq, owner, fn}]
var _observers: Dictionary = {}
var _seq: int = 0


func intercept(type: String, fn: Callable, priority: int = 0, owner: String = "") -> void:
	_add(_interceptors, type, fn, priority, owner)


func observe(type: String, fn: Callable, priority: int = 0, owner: String = "") -> void:
	_add(_observers, type, fn, priority, owner)


func _add(table: Dictionary, type: String, fn: Callable, priority: int, owner: String) -> void:
	_seq += 1
	if not table.has(type):
		table[type] = []
	table[type].append({"prio": priority, "seq": _seq, "owner": owner, "fn": fn})
	(table[type] as Array).sort_custom(_before)


static func _before(a: Dictionary, b: Dictionary) -> bool:
	if a["prio"] != b["prio"]:
		return a["prio"] < b["prio"]
	return a["seq"] < b["seq"]


func unsubscribe_owner(owner: String) -> int:
	var removed := 0
	for table in [_interceptors, _observers]:
		for type in table:
			var arr: Array = table[type]
			var i := arr.size() - 1
			while i >= 0:
				if arr[i]["owner"] == owner:
					arr.remove_at(i)
					removed += 1
				i -= 1
	return removed


## Suscripciones aplicables a un tipo (especificas + comodin), en orden estable.
func interceptors_for(type: String) -> Array:
	return _merged(_interceptors, type)


func observers_for(type: String) -> Array:
	return _merged(_observers, type)


func _merged(table: Dictionary, type: String) -> Array:
	var out: Array = []
	if table.has(type):
		out.append_array(table[type])
	if table.has("*"):
		out.append_array(table["*"])
	if table.has(type) and table.has("*"):
		out.sort_custom(_before)
	return out


## Libera todas las suscripciones (rompe ciclos de referencias con el motor).
func clear() -> void:
	_interceptors.clear()
	_observers.clear()
