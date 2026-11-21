class_name ScriptValue
extends RefCounted
## Conversion de datos entre el motor y los scripts: solo datos puros cruzan la frontera.

const MAX_DEPTH := 12


## Convierte a datos de script (int -> float, StringName -> String). Rechaza todo lo demas
## (objetos, callables, vectores...). Devuelve {"ok", "value", "error"}.
static func to_script(v: Variant, depth: int = 0) -> Dictionary:
	if depth > MAX_DEPTH:
		return {"ok": false, "value": null, "error": "estructura demasiado profunda"}
	if v == null or v is bool or v is String:
		return {"ok": true, "value": v, "error": ""}
	if v is int:
		return {"ok": true, "value": float(v), "error": ""}
	if v is float:
		if is_nan(v) or is_inf(v):
			return {"ok": true, "value": 0.0, "error": ""}
		return {"ok": true, "value": v, "error": ""}
	if v is StringName:
		return {"ok": true, "value": str(v), "error": ""}
	if v is Array:
		var out: Array = []
		for x in v:
			var r := to_script(x, depth + 1)
			if not r["ok"]:
				return r
			out.append(r["value"])
		return {"ok": true, "value": out, "error": ""}
	if v is Dictionary:
		var m := {}
		for k in v:
			if not (k is String or k is StringName):
				return {"ok": false, "value": null, "error": "clave de mapa no textual"}
			var r2 := to_script(v[k], depth + 1)
			if not r2["ok"]:
				return r2
			m[str(k)] = r2["value"]
		return {"ok": true, "value": m, "error": ""}
	return {"ok": false, "value": null, "error": "tipo no permitido en la frontera del script"}


## Validacion de un valor que el script entrega al motor (p. ej. `set_var`, `emit`): solo escalares
## y colecciones pequenas. Devuelve "" si es valido, o el motivo.
static func check_plain(v: Variant, max_nodes: int = 64) -> String:
	var count := [0]
	return _check(v, 0, count, max_nodes)


static func _check(v: Variant, depth: int, count: Array, max_nodes: int) -> String:
	count[0] += 1
	if count[0] > max_nodes:
		return "valor demasiado grande (max %d elementos)" % max_nodes
	if depth > 4:
		return "valor demasiado anidado"
	if v == null or v is bool or v is float or v is int:
		return ""
	if v is String:
		return "" if (v as String).length() <= 256 else "texto demasiado largo"
	if v is Array:
		for x in v:
			var e := _check(x, depth + 1, count, max_nodes)
			if e != "":
				return e
		return ""
	if v is Dictionary:
		for k in v:
			var e2 := _check(v[k], depth + 1, count, max_nodes)
			if e2 != "":
				return e2
		return ""
	return "tipo no permitido"
