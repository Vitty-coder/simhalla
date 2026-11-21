class_name AIReactionPolicy
extends RefCounted
## Politica de reacciones de una IA: decide si una reaccion YA elegible (el motor
## comprobo coste, restricciones y objetivo) se ejecuta o se declina.
##
## "reactions": {"default": "allow|decline",
##   "rules": [{"ability": "counter" | "*", "decision": "allow|decline", "when": {...}}]}
## La primera regla cuya habilidad coincide y cuyo `when` se cumple decide; si
## ninguna, `default` (allow si falta). Sin politica, las reacciones se ejecutan
## siempre (comportamiento de la fase 3). Condiciones: ambito "reaction"
## (self.*, mem.*, target.*, predict.*, event.amount, enemy.*, ally.*, turn, time).
## Declinar no consume RNG ni recursos; queda registrado (`reaction_declined`).

const DECISIONS := ["allow", "decline"]

var default_allow: bool = true
var rules: Array = []


static func validate(cfg: Variant, where: String = "ia reactions") -> Array:
	var errs: Array = []
	if not (cfg is Dictionary):
		return ["%s: debe ser un objeto" % where]
	for k in cfg:
		if not ["default", "rules"].has(str(k)):
			errs.append("%s: propiedad desconocida '%s'" % [where, str(k)])
	if cfg.has("default") and not DECISIONS.has(str(cfg["default"])):
		errs.append("%s.default: use allow|decline" % where)
	var rs: Variant = cfg.get("rules", [])
	if not (rs is Array):
		errs.append("%s.rules: debe ser una lista" % where)
		return errs
	if (rs as Array).size() > 64:
		errs.append("%s.rules: maximo 64 reglas" % where)
	for i in (rs as Array).size():
		var r: Variant = rs[i]
		var w := "%s.rules[%d]" % [where, i]
		if not (r is Dictionary) or str(r.get("ability", "")) == "":
			errs.append("%s: requiere 'ability' (id o '*')" % w)
			continue
		for k in r:
			if not ["ability", "decision", "when"].has(str(k)):
				errs.append("%s: propiedad desconocida '%s'" % [w, str(k)])
		if r.has("decision") and not DECISIONS.has(str(r["decision"])):
			errs.append("%s.decision: use allow|decline" % w)
		if r.has("when"):
			errs.append_array(AIConditions.validate(r["when"], w, "reaction"))
	return errs


static func from_dict(cfg: Dictionary) -> AIReactionPolicy:
	var p := AIReactionPolicy.new()
	p.default_allow = str(cfg.get("default", "allow")) == "allow"
	p.rules = (cfg.get("rules", []) as Array).duplicate(true)
	return p


func referenced_abilities() -> Array:
	return rules.map(func(r): return str(r["ability"])).filter(func(a): return a != "*")


## req: {ability_id, target_id, event:{type, source, target, amount}} -> {allow, reason, rule}
func decide(view: Dictionary, req: Dictionary) -> Dictionary:
	var ab := str(req["ability_id"])
	var tid := str(req["target_id"])
	var target: Variant = view["self"] if tid == view["self"]["id"] else null
	if target == null:
		for o in view["others"]:
			if o["id"] == tid:
				target = o
	var ctx := {"view": view, "target": target, "predict": AIPredictor.evaluate(view, ab, tid), "event": req.get("event", {})}
	for i in rules.size():
		var r: Dictionary = rules[i]
		if str(r["ability"]) != "*" and str(r["ability"]) != ab:
			continue
		if not AIConditions.holds(r.get("when", {}), ctx):
			continue
		return {"allow": str(r.get("decision", "allow")) == "allow", "reason": "rule_%d" % i, "rule": i}
	return {"allow": default_allow, "reason": "default", "rule": -1}
