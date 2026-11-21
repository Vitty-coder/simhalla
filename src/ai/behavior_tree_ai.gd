class_name BehaviorTreeAI
extends AIController
## IA de arbol de comportamiento declarativo. En cada decision se recorre el arbol
## (un "tick") hasta que una hoja produce una decision; no hay estado entre ticks
## (el estado persistente vive en la memoria, via `remember`).
##
## {"type":"behavior_tree","root":{"type":"selector","children":[
##    {"type":"sequence","children":[
##       {"type":"condition","when":{"self.hp_ratio":{"lt":0.3}}},
##       {"type":"action","ability":"mend","target":"self"}]},
##    {"type":"strategy","strategy":{"type":"scored","weights":{"damage":1}}},
##    {"type":"wait","reason":"nada_que_hacer"}]}}
##
## Nodos (estado devuelto: success | failure):
##   selector  {children}   primer hijo que tiene exito (si uno produce decision, el tick termina)
##   sequence  {children}   hijos en orden; falla en el primero que falla; un hijo que produce decision
##                          termina el tick con exito (sirve de "guardas + accion")
##   condition {when}       exito si se cumple (ambito estado: self, mem, enemy, ally, turn...)
##   action    {ability, target?, when?, remember?}   como una regla de priority_list; falla si no es
##                          legal, no hay objetivo o no se cumple `when`; si no, produce la decision
##   strategy  {strategy}   delega en passive|priority_list|scored; exito si propone una habilidad
##   wait      {reason?}    produce "esperar" (reservar)
##   not       {child}      invierte exito/fallo (no invierte decisiones: si el hijo decide, se mantiene)
##   succeed   {child}      exito siempre (el hijo puede producir decision)
## Sin decision al terminar: espera ("bt_no_decision"). Limites: 64 nodos, profundidad 8.
## Los nodos action/strategy no pueden contener otro arbol ni maquinas de estados.

const NODE_TYPES := ["selector", "sequence", "condition", "action", "strategy", "wait", "not", "succeed"]
const MAX_NODES := 64
const MAX_DEPTH := 8
const TRACE_MAX := 32

var root: Dictionary = {}
var _actions: Dictionary = {} ## ruta -> PriorityListAI de una regla
var _strategies: Dictionary = {} ## ruta -> AIController


static func validate(cfg: Dictionary) -> Array:
	var errs: Array = []
	for k in cfg:
		if not ["type", "root", "reactions"].has(str(k)):
			errs.append("ia behavior_tree: propiedad desconocida '%s'" % str(k))
	if not (cfg.get("root") is Dictionary):
		return errs + ["ia behavior_tree: 'root' debe ser un nodo (objeto)"]
	var count := [0]
	_validate_node(cfg["root"], "root", 1, count, errs)
	return errs


static func _validate_node(n: Variant, path: String, depth: int, count: Array, errs: Array) -> void:
	count[0] += 1
	if count[0] == MAX_NODES + 1:
		errs.append("ia behavior_tree: maximo %d nodos" % MAX_NODES)
	if count[0] > MAX_NODES:
		return
	if depth > MAX_DEPTH:
		errs.append("ia behavior_tree.%s: profundidad maxima %d" % [path, MAX_DEPTH])
		return
	if not (n is Dictionary) or not NODE_TYPES.has(str(n.get("type", ""))):
		errs.append("ia behavior_tree.%s: tipo de nodo desconocido (use: %s)" % [path, ", ".join(NODE_TYPES)])
		return
	var t := str(n["type"])
	var allowed: Array = ["type"]
	match t:
		"selector", "sequence":
			allowed.append("children")
			var ch: Variant = n.get("children")
			if not (ch is Array) or (ch as Array).is_empty():
				errs.append("ia behavior_tree.%s: 'children' debe ser una lista no vacia" % path)
			else:
				for i in (ch as Array).size():
					_validate_node(ch[i], "%s.children[%d]" % [path, i], depth + 1, count, errs)
		"not", "succeed":
			allowed.append("child")
			_validate_node(n.get("child"), path + ".child", depth + 1, count, errs)
		"condition":
			allowed.append("when")
			if not n.has("when"):
				errs.append("ia behavior_tree.%s: falta 'when'" % path)
			else:
				errs.append_array(AIConditions.validate(n["when"], "ia behavior_tree." + path, "state"))
		"action":
			allowed.append_array(["ability", "target", "when", "remember"])
			errs.append_array(PriorityListAI.validate({"rules": [_rule_of(n)]}).map(func(e): return "%s (nodo %s)" % [e, path]))
		"strategy":
			allowed.append("strategy")
			var s: Variant = n.get("strategy")
			if not (s is Dictionary) or not ["passive", "priority_list", "scored", "script"].has(str(s.get("type", ""))):
				errs.append("ia behavior_tree.%s: 'strategy' debe ser passive|priority_list|scored|script" % path)
			else:
				for e in AIFactory.build(s)["errors"]:
					errs.append("ia behavior_tree.%s: %s" % [path, str(e)])
		"wait":
			allowed.append("reason")
	for k in n:
		if not allowed.has(str(k)):
			errs.append("ia behavior_tree.%s: propiedad desconocida '%s'" % [path, str(k)])


static func _rule_of(n: Dictionary) -> Dictionary:
	var r := {"ability": n.get("ability", "")}
	for k in ["target", "when", "remember"]:
		if n.has(k):
			r[k] = n[k]
	return r


## Requiere validate() previa correcta.
static func from_dict(cfg: Dictionary) -> BehaviorTreeAI:
	var ai := BehaviorTreeAI.new()
	ai.root = (cfg["root"] as Dictionary).duplicate(true)
	ai._build(ai.root, "root")
	return ai


func _build(n: Dictionary, path: String) -> void:
	match str(n["type"]):
		"selector", "sequence":
			for i in (n["children"] as Array).size():
				_build(n["children"][i], "%s.children[%d]" % [path, i])
		"not", "succeed":
			_build(n["child"], path + ".child")
		"action":
			_actions[path] = PriorityListAI.from_dict({"rules": [BehaviorTreeAI._rule_of(n)]})
		"strategy":
			_strategies[path] = AIFactory.build(n["strategy"])["ai"]


func ai_id() -> String:
	return "behavior_tree"


func wants_memory() -> bool:
	return true


func referenced_abilities() -> Array:
	var out: Array = super.referenced_abilities()
	for p in _actions:
		out.append_array((_actions[p] as AIController).referenced_abilities())
	for p in _strategies:
		out.append_array((_strategies[p] as AIController).referenced_abilities())
	return out


func bind_scripts(scripts: Dictionary, lim: ScriptLimits) -> Array:
	var errs: Array = []
	for p in _strategies:
		errs.append_array((_strategies[p] as AIController).bind_scripts(scripts, lim))
	return errs


func decide(view: Dictionary) -> AIDecision:
	var trace: Array = []
	var res := _tick(root, "root", view, trace)
	var d: AIDecision = res["decision"]
	if d == null:
		d = AIDecision.wait("bt_no_decision")
	d.details["tree"] = trace
	return d


## Devuelve {"ok": bool, "decision": AIDecision|null}.
func _tick(n: Dictionary, path: String, view: Dictionary, trace: Array) -> Dictionary:
	var out := {"ok": false, "decision": null}
	match str(n["type"]):
		"selector":
			for i in (n["children"] as Array).size():
				var r := _tick(n["children"][i], "%s.children[%d]" % [path, i], view, trace)
				if r["ok"] or r["decision"] != null:
					return r
		"sequence":
			for i in (n["children"] as Array).size():
				var r2 := _tick(n["children"][i], "%s.children[%d]" % [path, i], view, trace)
				if r2["decision"] != null:
					return {"ok": true, "decision": r2["decision"]}
				if not r2["ok"]:
					return out
			out["ok"] = true
		"condition":
			out["ok"] = AIConditions.holds(n["when"], {"view": view, "target": null, "predict": null, "event": null})
			_note(trace, path, out["ok"])
		"action":
			var d: AIDecision = (_actions[path] as PriorityListAI).decide(view)
			var ok := d.kind == AIDecision.Kind.ABILITY
			_note(trace, path, ok)
			if ok:
				d.reason = "bt:" + path
				d.details.erase("discarded")
				return {"ok": true, "decision": d}
		"strategy":
			var sd: AIDecision = (_strategies[path] as AIController).decide(view)
			var sok := sd.kind == AIDecision.Kind.ABILITY
			_note(trace, path, sok)
			if sok:
				sd.reason = "bt:%s/%s" % [path, sd.reason]
				return {"ok": true, "decision": sd}
		"wait":
			_note(trace, path, true)
			return {"ok": true, "decision": AIDecision.wait(str(n.get("reason", "bt_wait")))}
		"not":
			var r3 := _tick(n["child"], path + ".child", view, trace)
			if r3["decision"] != null:
				return r3
			out["ok"] = not r3["ok"]
		"succeed":
			var r4 := _tick(n["child"], path + ".child", view, trace)
			if r4["decision"] != null:
				return r4
			out["ok"] = true
	return out


func _note(trace: Array, path: String, ok: bool) -> void:
	if trace.size() < TRACE_MAX:
		trace.append({"node": path, "ok": ok})
