class_name StateMachineAI
extends AIController
## IA de maquina de estados: cada estado delega en una estrategia (passive,
## priority_list o scored) y puede transitar a otro estado segun condiciones.
##
## {"type":"state_machine","initial":"opening",
##  "states":{
##    "opening":{"strategy":{"type":"priority_list","rules":[...]},
##               "transitions":[{"to":"desperate","when":{"self.hp_ratio":{"lt":0.3}}}]},
##    "desperate":{"strategy":{"type":"scored","weights":{...}},
##                 "transitions":[{"to":"opening","when":{"self.hp_ratio":{"ge":0.6}}}]}}}
##
## El estado actual vive en la memoria (`memory.state`). En cada decision se evaluan
## las transiciones del estado actual en orden (la primera cuyo `when` se cumple gana;
## como maximo UNA por decision, sin cadenas) y se decide con la estrategia del
## estado resultante. El cambio se propone como memory_op {op:"state"}.
## `state_turns` (condicion) = turnos propios transcurridos en el estado.
## Una transicion puede llevar "remember" ({set,incr}) como las reglas.
## Las estrategias de estado no pueden ser otra state_machine (sin anidacion).

const MAX_STATES := 16

var initial: String = ""
var states: Dictionary = {} ## nombre -> {"ai": AIController, "transitions": Array}


static func validate(cfg: Dictionary) -> Array:
	var errs: Array = []
	for k in cfg:
		if not ["type", "initial", "states", "reactions"].has(str(k)):
			errs.append("ia state_machine: propiedad desconocida '%s'" % str(k))
	var st: Variant = cfg.get("states", null)
	if not (st is Dictionary) or (st as Dictionary).is_empty():
		return errs + ["ia state_machine: 'states' debe ser un objeto no vacio"]
	if (st as Dictionary).size() > MAX_STATES:
		errs.append("ia state_machine: maximo %d estados" % MAX_STATES)
	if not st.has(str(cfg.get("initial", ""))):
		errs.append("ia state_machine: 'initial' debe nombrar un estado existente")
	for name in st:
		var s: Variant = st[name]
		var w := "ia state_machine.states.%s" % str(name)
		if not str(name).is_valid_identifier():
			errs.append("%s: nombre de estado invalido" % w)
		if not (s is Dictionary) or not (s.get("strategy") is Dictionary):
			errs.append("%s: requiere 'strategy' (objeto)" % w)
			continue
		for k in s:
			if not ["strategy", "transitions"].has(str(k)):
				errs.append("%s: propiedad desconocida '%s'" % [w, str(k)])
		if str(s["strategy"].get("type", "")) == "state_machine":
			errs.append("%s: una estrategia de estado no puede ser state_machine" % w)
		else:
			var built := AIFactory.build(s["strategy"])
			for e in built["errors"]:
				errs.append("%s: %s" % [w, str(e)])
		var trs: Variant = s.get("transitions", [])
		if not (trs is Array):
			errs.append("%s.transitions: debe ser una lista" % w)
			continue
		for i in (trs as Array).size():
			var t: Variant = trs[i]
			var tw := "%s.transitions[%d]" % [w, i]
			if not (t is Dictionary) or not st.has(str(t.get("to", ""))):
				errs.append("%s: 'to' debe nombrar un estado existente" % tw)
				continue
			for k in t:
				if not ["to", "when", "remember"].has(str(k)):
					errs.append("%s: propiedad desconocida '%s'" % [tw, str(k)])
			errs.append_array(AIConditions.validate(t.get("when", {}), tw, "state"))
			if t.has("remember"):
				errs.append_array(PriorityListAI.remember_errors(t["remember"], tw + ".remember"))
	return errs


## Requiere validate() previa correcta.
static func from_dict(cfg: Dictionary) -> StateMachineAI:
	var ai := StateMachineAI.new()
	ai.initial = str(cfg["initial"])
	for name in cfg["states"]:
		var s: Dictionary = cfg["states"][name]
		ai.states[str(name)] = {
			"ai": AIFactory.build(s["strategy"])["ai"],
			"transitions": (s.get("transitions", []) as Array).duplicate(true),
		}
	return ai


func ai_id() -> String:
	return "state_machine"


func wants_memory() -> bool:
	return true


func referenced_abilities() -> Array:
	var out: Array = super.referenced_abilities()
	for name in states:
		out.append_array((states[name]["ai"] as AIController).referenced_abilities())
	return out


func bind_scripts(scripts: Dictionary, lim: ScriptLimits) -> Array:
	var errs: Array = []
	for name in states:
		errs.append_array((states[name]["ai"] as AIController).bind_scripts(scripts, lim))
	return errs


func decide_reaction(view: Dictionary, req: Dictionary) -> Dictionary:
	var cur := _current(view)
	var sub: AIController = states[cur]["ai"]
	if sub.has_reaction_policy():
		return sub.decide_reaction(view, req)
	return super.decide_reaction(view, req)


func has_reaction_policy() -> bool:
	if reaction_policy != null:
		return true
	for name in states:
		if (states[name]["ai"] as AIController).has_reaction_policy():
			return true
	return false


func _current(view: Dictionary) -> String:
	var cur := str(view["self"]["memory"].get("state", ""))
	return cur if states.has(cur) else initial


func decide(view: Dictionary) -> AIDecision:
	var cur := _current(view)
	var ops: Array = []
	var moved_from := ""
	var ctx := {"view": view, "target": null, "predict": null, "event": null}
	var next := cur
	var trans_idx := -1
	if str(view["self"]["memory"].get("state", "")) == "":
		ops.append({"op": "state", "value": cur}) # fija el estado inicial en la memoria
	var trs: Array = states[cur]["transitions"]
	for i in trs.size():
		if AIConditions.holds(trs[i].get("when", {}), ctx):
			next = str(trs[i]["to"])
			trans_idx = i
			break
	if next != cur:
		moved_from = cur
		ops = [{"op": "state", "value": next}]
		if trs[trans_idx].has("remember"):
			ops.append_array(PriorityListAI.remember_ops(trs[trans_idx]["remember"]))
	var sub: AIController = states[next]["ai"]
	var sub_view := view
	if next != cur:
		# la estrategia del nuevo estado ve su contador de estado a cero
		sub_view = view.duplicate(false)
		sub_view["self"] = (view["self"] as Dictionary).duplicate(false)
		var mem: Dictionary = (view["self"]["memory"] as Dictionary).duplicate(false)
		mem["state"] = next
		mem["state_since"] = int(mem.get("own_turns", 0))
		sub_view["self"]["memory"] = mem
	var d := sub.decide(sub_view)
	d.details["state"] = next
	if moved_from != "":
		d.details["transition"] = {"from": moved_from, "to": next, "rule": trans_idx}
	var merged: Array = ops.duplicate()
	merged.append_array(d.memory_ops)
	d.memory_ops = merged
	return d
