class_name AiHost
extends RefCounted
## Anfitrion de la API de IA: solo consultas de prediccion sobre la VISTA (datos). No hay
## operaciones de combate, ni RNG, ni variables: la IA propone, el motor decide.

var limits: ScriptLimits


func _init(lim: ScriptLimits) -> void:
	limits = lim


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "value": null, "error": msg, "cost": 0}


func call_api(name: String, a: Array) -> Dictionary:
	match name:
		"predict":
			if not (a[0] is Dictionary) or not (a[0] as Dictionary).has("self") or not (a[1] is String) or not (a[2] is String):
				return _fail("predict(vista, habilidad, objetivo): argumentos invalidos")
			var ev := AIPredictor.evaluate(a[0], a[1], a[2])
			var conv := ScriptValue.to_script(ev)
			if not conv["ok"]:
				return _fail("predict: " + str(conv["error"]))
			return {"ok": true, "value": conv["value"], "error": "", "cost": 8}
		"observed_ratio":
			if not (a[0] is Dictionary) or not (a[0] as Dictionary).has("self") or not (a[1] is String) or not (a[2] is String) or not (a[3] is String):
				return _fail("observed_ratio(vista, objetivo, tipo, elemento): argumentos invalidos")
			var r := AIPredictor.observed_ratio(a[0], a[1], a[2], a[3])
			return {"ok": true, "value": {"ratio": float(r["ratio"]), "known": bool(r["known"])}, "error": "", "cost": 4}
	return _fail("funcion de API sin implementar '%s'" % name)
