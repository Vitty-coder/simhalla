class_name PriorityListAI
extends AIController
## IA declarativa de prioridades fijas: la primera regla aplicable gana.
##
## {"type":"priority_list","rules":[
##   {"ability":"heal","target":"self","when":{"self.hp_ratio":{"lt":0.4}}},
##   {"ability":"smite","target":"lowest_hp_enemy","when":{"predict.lethal":{"eq":1}},
##    "remember":{"incr":{"finishers":1}}},
##   {"ability":"basic_attack","target":"lowest_hp_enemy"}]}
##
## target: self | first_enemy | lowest_hp_enemy | highest_hp_enemy |
##         lowest_hp_ally | first_ally | last_attacker (memoria: ultimo rival que me dano)
## when (opcional): ver AIConditions (propias, memoria, grupos, objetivo y prediccion).
## remember (opcional): {"set": {var: valor}, "incr": {var: n}}; se aplica si la regla se ejecuta.
## Desempates deterministas (orden de aparicion en la vista). Sin azar.

const TARGETS := ["self", "first_enemy", "lowest_hp_enemy", "highest_hp_enemy", "lowest_hp_ally", "first_ally", "last_attacker"]
const OPS := AIConditions.OPS
const TARGET_KEYS := ["target.", "predict.", "event."]

var rules: Array = []


static func validate(cfg: Dictionary) -> Array:
	var errs: Array = []
	var rs: Variant = cfg.get("rules", null)
	if not (rs is Array):
		return ["ia priority_list: 'rules' debe ser una lista"]
	for i in (rs as Array).size():
		var r: Variant = rs[i]
		if not (r is Dictionary) or str(r.get("ability", "")) == "":
			errs.append("ia rules[%d]: requiere 'ability'" % i)
			continue
		if not TARGETS.has(str(r.get("target", "first_enemy"))):
			errs.append("ia rules[%d]: target desconocido '%s'" % [i, str(r.get("target"))])
		for k in r:
			if not ["ability", "target", "when", "remember"].has(str(k)):
				errs.append("ia rules[%d]: propiedad desconocida '%s'" % [i, str(k)])
		var w: Variant = r.get("when", {})
		if not (w is Dictionary):
			errs.append("ia rules[%d]: 'when' debe ser un objeto" % i)
		else:
			errs.append_array(AIConditions.validate(w, "ia rules[%d]" % i, "rule"))
		if r.has("remember"):
			errs.append_array(remember_errors(r["remember"], "ia rules[%d].remember" % i))
	return errs


## Valida {"set": {...}, "incr": {...}} (compartido con la maquina de estados).
static func remember_errors(rem: Variant, where: String) -> Array:
	var errs: Array = []
	if not (rem is Dictionary):
		return ["%s: debe ser un objeto {set, incr}" % where]
	for k in rem:
		if not ["set", "incr"].has(str(k)) or not (rem[k] is Dictionary):
			errs.append("%s: solo 'set'/'incr' (objetos)" % where)
			continue
		for var_name in rem[k]:
			var v: Variant = rem[k][var_name]
			var ok: bool = v is float or v is int or (str(k) == "set" and (v is bool or v is String))
			if not ok:
				errs.append("%s.%s.%s: valor no permitido" % [where, str(k), str(var_name)])
			if not str(var_name).is_valid_identifier():
				errs.append("%s.%s: nombre de variable invalido '%s'" % [where, str(k), str(var_name)])
	return errs


static func remember_ops(rem: Dictionary) -> Array:
	var ops: Array = []
	for k in ["set", "incr"]:
		if rem.has(k):
			for var_name in rem[k]:
				ops.append({"op": k, "key": str(var_name), "value": rem[k][var_name]})
	return ops


static func from_dict(cfg: Dictionary) -> PriorityListAI:
	var ai := PriorityListAI.new()
	ai.rules = (cfg.get("rules", []) as Array).duplicate(true)
	return ai


func ai_id() -> String:
	return "priority_list"


func wants_memory() -> bool:
	var s := JSON.stringify(rules)
	return super.wants_memory() or s.contains("\"mem.") or s.contains("predict.") or s.contains("last_attacker") or s.contains("remember") or s.contains("state_turns")


func referenced_abilities() -> Array:
	var out: Array = super.referenced_abilities()
	for r in rules:
		out.append(str(r["ability"]))
	return out


func decide(view: Dictionary) -> AIDecision:
	var legal: Dictionary = {}
	for la in view["legal_actions"]:
		legal[la["ability_id"]] = la
	var discarded: Array = []
	for i in rules.size():
		var rule: Dictionary = rules[i]
		var ab: String = str(rule["ability"])
		if not legal.has(ab):
			discarded.append({"rule": i, "why": "no_legal"})
			continue
		var when: Dictionary = rule.get("when", {})
		var pre := {}
		var post := {}
		for k in when:
			(post if _needs_target(str(k)) else pre)[k] = when[k]
		var ctx := {"view": view, "target": null, "predict": null, "event": null}
		if not AIConditions.holds(pre, ctx):
			discarded.append({"rule": i, "why": "condition"})
			continue
		var targets: Array = _pick_targets(view, legal[ab], str(rule.get("target", "first_enemy")))
		if targets.is_empty():
			discarded.append({"rule": i, "why": "no_target"})
			continue
		if not post.is_empty():
			ctx["target"] = _entity(view, str(targets[0]))
			ctx["predict"] = AIPredictor.evaluate(view, ab, str(targets[0]))
			if not AIConditions.holds(post, ctx):
				discarded.append({"rule": i, "why": "condition"})
				continue
		var d := AIDecision.use(ab, targets, "rule_%d" % i, {"discarded": discarded})
		if rule.has("remember"):
			d.memory_ops = remember_ops(rule["remember"])
		return d
	return AIDecision.wait("no_rule_applies", {"discarded": discarded})


static func _needs_target(key: String) -> bool:
	for p in TARGET_KEYS:
		if key.begins_with(p):
			return true
	return false


static func _entity(view: Dictionary, id: String) -> Variant:
	if id == view["self"]["id"]:
		return view["self"]
	for o in view["others"]:
		if o["id"] == id:
			return o
	return null


func _pick_targets(view: Dictionary, action: Dictionary, selector: String) -> Array:
	var allowed: Array = action["targets"]
	if selector == "self":
		return [view["self"]["id"]] if allowed.has(view["self"]["id"]) else []
	if selector == "last_attacker":
		var la := str(view["self"]["memory"].get("last_hit_by", ""))
		return [la] if la != "" and allowed.has(la) else []
	var want_enemy: bool = selector.ends_with("enemy")
	var pool: Array = []
	for o in view["others"]:
		if o["alive"] and allowed.has(o["id"]) and ((o["relation"] == "enemy") == want_enemy):
			pool.append(o)
	if pool.is_empty():
		return []
	var best: Dictionary = pool[0]
	if selector.begins_with("lowest_hp"):
		for o in pool:
			if float(o.get("hp", INF)) < float(best.get("hp", INF)):
				best = o
	elif selector.begins_with("highest_hp"):
		for o in pool:
			if float(o.get("hp", -INF)) > float(best.get("hp", -INF)):
				best = o
	return [best["id"]]
