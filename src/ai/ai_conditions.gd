class_name AIConditions
extends RefCounted
## Condiciones declarativas de la IA, evaluadas SOLO sobre la vista de lectura.
##
## `when` = {"<ruta>": {"<op>": valor, ...}, ...}; todas deben cumplirse.
## op: lt le gt ge eq ne. Los booleanos cuentan como 1/0. Una ruta desconocida o
## sin dato visible hace falsa la condicion (nunca se infiere informacion oculta).
##
## Rutas (ambito "state": estrategia/transiciones; "rule": ademas objetivo y prediccion;
## "reaction": ademas `event.amount`):
##   self.hp  self.hp_ratio  self.res.<id>  self.stat.<STAT>  self.status.<id> (pilas)
##   mem.<var>            variable de memoria (0 si no existe)
##   enemy.alive_count  enemy.lowest_hp_ratio  ally.alive_count  ally.lowest_hp_ratio
##   turn  time  state_turns (turnos propios en el estado actual de una maquina)
##   target.hp  target.hp_ratio  target.res.<id>  target.status.<id>     (rule/reaction)
##   predict.damage  predict.damage_max  predict.hit_chance  predict.lethal
##   predict.lethal_potential  predict.heal                                (rule/reaction)
##   predict.time_to_turn (virtual; sin dato hasta observar al rival)  predict.reactions_seen (reacciones distintas observadas del objetivo)
##   event.amount                                                          (reaction)

const OPS := ["lt", "le", "gt", "ge", "eq", "ne"]
const STATE_ROOTS := ["self", "mem", "enemy", "ally"]
const STATE_LEAVES := ["turn", "time", "state_turns"]
const RULE_ROOTS := ["target", "predict"]
const PREDICT_KEYS := ["damage", "damage_max", "hit_chance", "lethal", "lethal_potential", "heal", "time_to_turn", "reactions_seen"]


## Valida un bloque `when`. scope: "state" | "rule" | "reaction".
static func validate(when: Variant, where: String, scope: String) -> Array:
	var errs: Array = []
	if not (when is Dictionary):
		return ["%s: 'when' debe ser un objeto" % where]
	for key in when:
		var k := str(key)
		if not _path_ok(k, scope):
			errs.append("%s.when: ruta desconocida o no permitida aqui '%s'" % [where, k])
		var cmp: Variant = when[key]
		if not (cmp is Dictionary) or (cmp as Dictionary).is_empty():
			errs.append("%s.when.%s: debe ser un objeto de comparadores" % [where, k])
			continue
		for op in cmp:
			if not OPS.has(str(op)):
				errs.append("%s.when.%s: comparador desconocido '%s'" % [where, k, str(op)])
			elif not (cmp[op] is float or cmp[op] is int or cmp[op] is bool):
				errs.append("%s.when.%s.%s: el valor debe ser numerico o booleano" % [where, k, str(op)])
	return errs


static func _path_ok(path: String, scope: String) -> bool:
	var parts := path.split(".")
	if parts.size() == 1:
		return STATE_LEAVES.has(parts[0])
	var root: String = parts[0]
	if STATE_ROOTS.has(root):
		match root:
			"self":
				return ["hp", "hp_ratio"].has(parts[1]) and parts.size() == 2 \
					or ["res", "stat", "status"].has(parts[1]) and parts.size() >= 3
			"mem":
				return parts.size() == 2
			_:
				return ["alive_count", "lowest_hp_ratio"].has(parts[1]) and parts.size() == 2
	if scope == "state":
		return false
	if root == "target":
		return ["hp", "hp_ratio"].has(parts[1]) and parts.size() == 2 \
			or ["res", "status"].has(parts[1]) and parts.size() >= 3
	if root == "predict":
		return parts.size() == 2 and PREDICT_KEYS.has(parts[1])
	if root == "event":
		return scope == "reaction" and parts.size() == 2 and parts[1] == "amount"
	return false


## ctx: {"view": Dictionary, "target": Dictionary|null, "predict": Dictionary|null, "event": Dictionary|null}
static func holds(when: Dictionary, ctx: Dictionary) -> bool:
	for key in when:
		var v: Variant = lookup(str(key), ctx)
		if v == null:
			return false
		var cmp: Dictionary = when[key]
		var f: float = v
		for op in cmp:
			var x: float = _num(cmp[op])
			match str(op):
				"lt":
					if not (f < x):
						return false
				"le":
					if not (f <= x):
						return false
				"gt":
					if not (f > x):
						return false
				"ge":
					if not (f >= x):
						return false
				"eq":
					if not is_equal_approx(f, x):
						return false
				"ne":
					if is_equal_approx(f, x):
						return false
	return true


static func _num(v: Variant) -> float:
	if v is bool:
		return 1.0 if v else 0.0
	return float(v)


## Devuelve float o null (sin dato).
static func lookup(path: String, ctx: Dictionary) -> Variant:
	var view: Dictionary = ctx["view"]
	var p := path.split(".")
	var me: Dictionary = view["self"]
	match p[0]:
		"turn":
			return float(view["turn"])
		"time":
			return float(view["time"])
		"state_turns":
			var mem: Dictionary = me["memory"]
			if str(mem.get("state", "")) == "":
				return 0.0 # aun sin estado fijado: primer turno en el estado inicial
			return float(int(mem.get("own_turns", 0)) - int(mem.get("state_since", 0)))
		"self":
			return _entity_value(me, p, true)
		"mem":
			var vars: Dictionary = me["memory"].get("vars", {})
			return _num(vars[p[1]]) if vars.has(p[1]) and (vars[p[1]] is float or vars[p[1]] is int or vars[p[1]] is bool) else 0.0
		"enemy", "ally":
			return _group_value(view, p[0], p[1])
		"target":
			var t: Variant = ctx.get("target", null)
			return _entity_value(t, p, false) if t is Dictionary else null
		"predict":
			var pr: Variant = ctx.get("predict", null)
			if not (pr is Dictionary) or not (pr as Dictionary).has(p[1]):
				return null
			var x: Variant = pr[p[1]]
			return _num(x) if (x is float or x is int or x is bool) else null
		"event":
			var ev: Variant = ctx.get("event", null)
			if ev is Dictionary and (ev as Dictionary).has(p[1]):
				return _num(ev[p[1]])
			return null
	return null


static func _entity_value(d: Dictionary, p: PackedStringArray, own: bool) -> Variant:
	match p[1]:
		"hp":
			return float(d["hp"]) if d.has("hp") else null
		"hp_ratio":
			if d.has("hp_ratio"):
				return float(d["hp_ratio"])
			if d.has("hp") and d.has("hp_max") and float(d["hp_max"]) > 0.0:
				return float(d["hp"]) / float(d["hp_max"])
			return null
		"res":
			var r: Dictionary = d.get("resources", {})
			return float(r[p[2]]) if p.size() > 2 and r.has(p[2]) else null
		"stat":
			if not own:
				return null
			var s: Dictionary = d.get("stats", {})
			return float(s[p[2]]) if p.size() > 2 and s.has(p[2]) else null
		"status":
			if not d.has("statuses") or p.size() < 3:
				return null # estado no visible = desconocido
			var n := 0.0
			for st in d["statuses"]:
				if str(st["id"]) == p[2]:
					n += float(st["stacks"])
			return n
	return null


static func _group_value(view: Dictionary, group: String, what: String) -> Variant:
	var want := "enemy" if group == "enemy" else "ally"
	var count := 0
	var lowest := INF
	for o in view["others"]:
		if str(o["relation"]) != want or not bool(o["alive"]):
			continue
		count += 1
		if o.has("hp") and o.has("hp_max") and float(o["hp_max"]) > 0.0:
			lowest = minf(lowest, float(o["hp"]) / float(o["hp_max"]))
	if what == "alive_count":
		return float(count)
	if what == "lowest_hp_ratio":
		return lowest if lowest != INF else null
	return null
