class_name Duration
extends RefCounted
## Duracion generica (estados, cooldowns, vida de invocaciones).
##
## Unidades (PROJECT.md 6.3):
##   target_turns   turnos del afectado (dueno)
##   caster_turns   turnos del lanzador
##   global_actions actuaciones globales (acciones resueltas de cualquier entidad)
##   time           tiempo virtual ATB (unidades)
##   events         N ocurrencias de un evento (con filtro)
##   permanent      sin caducidad
## Convenciones (provisionales, D-040): los estados decrementan AL FINAL del turno
## de la entidad correspondiente y el turno en que se aplicaron no cuenta (un
## estado de 2 turnos afecta a los 2 turnos completos siguientes); los cooldowns
## decrementan AL INICIO del turno del dueno (cooldown 3 = reutilizable 3 turnos
## despues). El decremento lo ejecuta DurationService, no esta clase.

const UNITS := ["target_turns", "caster_turns", "global_actions", "time", "events", "permanent"]
const FILTER_KEYS := ["source", "target"] ## valor: "self" (el dueno) | "other"

var unit: String = "permanent"
var amount: float = 0.0
var remaining: float = 0.0
var event_type: String = ""
var event_filter: Dictionary = {}
var expires_at: int = -1 ## microunidades (solo unit == time)
var skip_turn: int = -1 ## turno cuyo final no cuenta
var skip_cause: int = -1 ## ACTION_STARTED cuya resolucion no cuenta (global_actions)


static func from_dict(d: Variant) -> Duration:
	var du := Duration.new()
	if d is float or d is int:
		du.unit = "target_turns"
		du.amount = float(d)
	elif d is Dictionary:
		du.unit = str(d.get("unit", "target_turns"))
		du.amount = float(d.get("amount", 0.0))
		du.event_type = str(d.get("event", ""))
		du.event_filter = (d.get("filter", {}) as Dictionary).duplicate()
	du.remaining = du.amount
	return du


## Errores de validacion de una especificacion de duracion.
static func validate(d: Variant, label: String) -> Array:
	var errs: Array = []
	if d is float or d is int:
		if float(d) <= 0.0:
			errs.append("%s: la duracion debe ser > 0" % label)
		return errs
	if not (d is Dictionary):
		return ["%s: la duracion debe ser un numero (turnos) o un objeto" % label]
	for k in d:
		if not ["unit", "amount", "event", "filter"].has(str(k)):
			errs.append("%s: propiedad desconocida '%s'" % [label, str(k)])
	var unit_v := str(d.get("unit", "target_turns"))
	if not UNITS.has(unit_v):
		errs.append("%s: unit desconocida '%s' (use %s)" % [label, unit_v, ", ".join(UNITS)])
		return errs
	if unit_v != "permanent":
		if not (d.get("amount", null) is float or d.get("amount", null) is int) or float(d.get("amount", 0)) <= 0.0:
			errs.append("%s: 'amount' debe ser un numero > 0" % label)
	if unit_v == "events":
		if str(d.get("event", "")) == "":
			errs.append("%s: la unidad 'events' requiere 'event'" % label)
		var f: Variant = d.get("filter", {})
		if not (f is Dictionary):
			errs.append("%s: 'filter' debe ser un objeto" % label)
		else:
			for k in f:
				if not FILTER_KEYS.has(str(k)) or not ["self", "other"].has(str(f[k])):
					errs.append("%s: filter.%s invalido (claves: source,target; valores: self,other)" % [label, str(k)])
	return errs


func is_permanent() -> bool:
	return unit == "permanent"


func reset() -> void:
	remaining = amount


func extend(by: float) -> void:
	remaining = maxf(remaining + by, 0.0)
	amount = maxf(amount + by, 0.0)


func to_dict() -> Dictionary:
	return {"unit": unit, "amount": amount, "remaining": remaining, "event": event_type}
