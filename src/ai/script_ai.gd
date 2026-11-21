class_name ScriptAI
extends AIController
## IA programada en SimScript: `{"type":"script","script":"mi_ia"}`.
##
## El script define `fn decide(view)` y devuelve un mapa:
##   {"ability": "id", "target": "id" | "targets": ["id", ...], "reason": "texto",
##    "remember": {"set": {...}, "incr": {...}}}      o      {"wait": true, "reason": "texto"}
## `view` es la misma vista limitada de solo lectura que reciben las demas IA (copia). La API de IA
## solo permite consultas (predict, observed_ratio) + funciones puras: sin operaciones de combate,
## sin RNG, sin variables propias del motor. El motor revalida la propuesta como siempre.
## Un error del script (limite, tipo, resultado invalido) NO aborta el combate: politica de fallback
## documentada (esperar) + evento `ai_fallback` con el motivo.

var script_id: String = ""
var program: ScriptProgram = null
var limits: ScriptLimits = ScriptLimits.new()


static func validate(cfg: Dictionary) -> Array:
	var errs: Array = []
	for k in cfg:
		if not ["type", "script", "reactions"].has(str(k)):
			errs.append("ia script: propiedad desconocida '%s'" % str(k))
	if not (cfg.get("script", null) is String) or not RegEx.create_from_string("^[a-z][a-z0-9_]{0,63}$").search(str(cfg.get("script", ""))):
		errs.append("ia script: 'script' debe ser un identificador en minusculas (archivo sin .sim)")
	return errs


static func from_dict(cfg: Dictionary) -> ScriptAI:
	var ai := ScriptAI.new()
	ai.script_id = str(cfg["script"])
	return ai


func ai_id() -> String:
	return "script:" + script_id


func wants_memory() -> bool:
	return true


## Enlaza el programa compilado de la entidad. Devuelve errores.
func bind_scripts(scripts: Dictionary, lim: ScriptLimits) -> Array:
	limits = lim
	if not scripts.has(script_id):
		return ["ia: el script '%s' no existe en la entidad" % script_id]
	program = scripts[script_id]
	return program.check_context(ScriptApi.AI)


func decide(view: Dictionary) -> AIDecision:
	if program == null:
		return _fallback("script_no_enlazado")
	var conv := ScriptValue.to_script(view)
	if not conv["ok"]:
		return _fallback("vista_no_convertible")
	var interp := ScriptInterpreter.new(program, limits, AiHost.new(limits), ScriptApi.AI)
	var res := interp.call_entry(ScriptProgram.ENTRY["ai"], [conv["value"]])
	if not bool(res["ok"]):
		return _fallback("script_error: " + str(res["error"]), int(res["instructions"]))
	var d := _to_decision(res["value"])
	if d == null:
		return _fallback("script_resultado_invalido", int(res["instructions"]))
	d.details["script"] = {"id": script_id, "instructions": int(res["instructions"])}
	return d


func _fallback(why: String, instructions: int = 0) -> AIDecision:
	var d := AIDecision.wait("script_fallback", {"error": why, "script": {"id": script_id, "instructions": instructions}})
	d.fallback = why
	return d


func _to_decision(v: Variant) -> AIDecision:
	if not (v is Dictionary):
		return null
	var m: Dictionary = v
	for k in m:
		if not ["ability", "target", "targets", "reason", "remember", "wait"].has(str(k)):
			return null
	var reason := str(m.get("reason", "script")) if m.get("reason", "script") is String else "script"
	if reason.length() > 64:
		reason = reason.substr(0, 64)
	var d: AIDecision
	if m.get("wait", false) == true:
		d = AIDecision.wait(reason)
	else:
		if not (m.get("ability", null) is String):
			return null
		var targets: Array = []
		if m.has("targets"):
			if not (m["targets"] is Array):
				return null
			for t in m["targets"]:
				if not (t is String):
					return null
				targets.append(t)
		elif m.has("target"):
			if not (m["target"] is String):
				return null
			targets.append(m["target"])
		d = AIDecision.use(m["ability"], targets, reason)
	if m.has("remember"):
		if not (m["remember"] is Dictionary) or not PriorityListAI.remember_errors(m["remember"], "remember").is_empty():
			return null
		d.memory_ops = PriorityListAI.remember_ops(m["remember"])
	return d
