class_name FormulaContext
extends RefCounted
## Resolvedor de variables de formulas: expone solo datos autorizados.
##
## Rutas: `caster.<STAT>` / `target.<STAT>` (cualquier estadistica efectiva,
## incluidas "ELEM_RES.fire"), `status.stacks|magnitude|shield` (en estados), `caster.hp`, `caster.hp_max`, `caster.hp_missing`,
## `caster.hp_ratio`, `caster.res.<recurso>` y `caster.res.<recurso>.max`.
## Tambien `target.*`. No expone objetos del motor ni del sistema.

var caster: CombatEntity = null
var target: CombatEntity = null
var status: StatusInstance = null ## para status.stacks / status.magnitude / status.shield


func _init(caster_: CombatEntity = null, target_: CombatEntity = null, status_: StatusInstance = null) -> void:
	caster = caster_
	target = target_
	status = status_


func resolver() -> Callable:
	return Callable(self, "resolve")


func resolve(parts: Array) -> Dictionary:
	if parts.size() < 2:
		return {"ok": false, "value": 0.0, "error": "variable invalida '%s'" % ".".join(parts)}
	if str(parts[0]) == "status":
		if status == null:
			return {"ok": false, "value": 0.0, "error": "'status' no disponible en este contexto"}
		match str(parts[1]):
			"stacks":
				return _ok(float(status.stacks))
			"magnitude":
				return _ok(status.magnitude)
			"shield":
				return _ok(status.shield)
		return {"ok": false, "value": 0.0, "error": "variable de estado desconocida '%s'" % str(parts[1])}
	var who: CombatEntity = null
	match str(parts[0]):
		"caster":
			who = caster
		"target":
			who = target
		_:
			return {"ok": false, "value": 0.0, "error": "origen desconocido '%s' (use caster/target)" % str(parts[0])}
	if who == null:
		return {"ok": false, "value": 0.0, "error": "'%s' no disponible en este contexto" % str(parts[0])}
	var rest: Array = parts.slice(1)
	var key: String = str(rest[0])
	if rest.size() == 1:
		match key:
			"hp":
				return _ok(who.hp)
			"hp_max":
				return _ok(who.hp_max())
			"hp_missing":
				return _ok(maxf(who.hp_max() - who.hp, 0.0))
			"hp_ratio":
				return _ok(who.hp_ratio())
	if key == "res" and rest.size() >= 2:
		var r: ResourceState = who.get_resource(str(rest[1]))
		if r == null:
			return {"ok": false, "value": 0.0, "error": "recurso desconocido '%s'" % str(rest[1])}
		if rest.size() == 3 and str(rest[2]) == "max":
			return _ok(r.max_value)
		if rest.size() == 2:
			return _ok(r.value)
		return {"ok": false, "value": 0.0, "error": "ruta de recurso invalida"}
	return _ok(who.stats.get_value(".".join(rest)))


static func _ok(v: float) -> Dictionary:
	return {"ok": true, "value": v, "error": ""}
