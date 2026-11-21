class_name EffectHost
extends RefCounted
## Anfitrion de la API de EFECTOS: traduce las llamadas permitidas de un script a operaciones del
## motor. Las entidades se identifican por id (texto); el script nunca recibe objetos.
## Toda operacion que cambia el combate pasa por el pipeline del motor (validada, interceptable
## y con eventos) y cuenta contra `max_mutations`. Tras un aborto del motor, toda llamada falla.

var ctx: ActionContext
var limits: ScriptLimits
var mutations: int = 0
var contract: Variant = null ## {max_damage?, max_heal?}: topes por ejecucion (null = sin contrato)
var damage_used: float = 0.0
var heal_used: float = 0.0
var _rng_stream: String = "script"


func _init(c: ActionContext, lim: ScriptLimits) -> void:
	ctx = c
	limits = lim


func _fail(msg: String) -> Dictionary:
	return {"ok": false, "value": null, "error": msg, "cost": 0}


func _ok(v: Variant, cost: int = 0) -> Dictionary:
	return {"ok": true, "value": v, "error": "", "cost": cost}


func _ent(v: Variant) -> CombatEntity:
	if not (v is String):
		return null
	return ctx.engine.get_entity(v)


func _mut() -> String:
	mutations += 1
	if mutations > limits.max_mutations:
		return "[limite] demasiadas operaciones de combate en una ejecucion (max %d)" % limits.max_mutations
	return ""


func call_api(name: String, a: Array) -> Dictionary:
	var eng := ctx.engine
	if eng.is_aborted():
		return _fail("el combate esta abortado")
	var kind := ScriptApi.kind_of(name)
	# validacion comun de identificadores de entidad (primer argumento de la mayoria)
	var e: CombatEntity = null
	if ["stat", "hp", "hp_max", "hp_ratio", "res", "res_max", "alive", "team", "enemies", "allies", "status_stacks", "has_tag",
			"deal_damage", "heal", "modify_resource", "apply_status", "remove_status", "attack_roll"].has(name):
		e = _ent(a[0])
		if e == null:
			return _fail("`%s`: entidad desconocida %s" % [name, str(a[0])])
	if kind == "mutate" or kind == "state" and name == "set_var":
		var m := _mut()
		if m != "":
			return _fail(m)
	if contract != null and ["apply_status", "remove_status", "modify_resource"].has(name):
		return _fail("[contrato] el contrato del efecto no cubre `%s()`" % name)
	match name:
		"stat":
			if not (a[1] is String) or not e.stats.has_stat(a[1]) and not (a[1] as String).begins_with("ELEM_"):
				return _fail("stat: estadistica desconocida '%s'" % str(a[1]))
			return _ok(e.stats.get_value(a[1]))
		"hp":
			return _ok(e.hp)
		"hp_max":
			return _ok(e.hp_max())
		"hp_ratio":
			return _ok(e.hp_ratio())
		"res":
			var r: ResourceState = e.get_resource(str(a[1]))
			return _ok(r.value if r != null else null)
		"res_max":
			var r2: ResourceState = e.get_resource(str(a[1]))
			return _ok(r2.max_value if r2 != null else null)
		"alive":
			return _ok(e.alive)
		"team":
			return _ok(e.team)
		"is_enemy":
			var x := _ent(a[0])
			var y := _ent(a[1])
			if x == null or y == null:
				return _fail("is_enemy: entidad desconocida")
			return _ok(eng.relation(x, y) == "enemy")
		"enemies", "allies":
			var want := "enemy" if name == "enemies" else "ally"
			var out: Array = []
			for o in eng.entities:
				if o.alive and eng.relation(e, o) == want:
					out.append(o.id)
			return _ok(out, out.size())
		"status_stacks":
			var n := 0
			for st in e.statuses:
				if st.def.id == str(a[1]):
					n += st.stacks
			return _ok(float(n))
		"has_tag":
			return _ok(e.tags.has(str(a[1])))
		"turn":
			return _ok(float(eng.turn_count))
		"time":
			return _ok(float(eng.scheduler.now) / float(Ruleset.TIME_SCALE))
		"get_var":
			return _ok(ctx.actor.script_vars.get(str(a[0]), null))
		"set_var":
			var key := str(a[0])
			if not (a[0] is String) or not RegEx.create_from_string("^[a-z][a-z0-9_]{0,31}$").search(key):
				return _fail("set_var: nombre de variable invalido (use minusculas, digitos y _)")
			var bad := ScriptValue.check_plain(a[1])
			if bad != "":
				return _fail("set_var: %s" % bad)
			if not ctx.actor.script_vars.has(key) and ctx.actor.script_vars.size() >= 64:
				return _fail("[limite] demasiadas variables de script (max 64)")
			ctx.actor.script_vars[key] = (a[1] as Variant).duplicate(true) if (a[1] is Array or a[1] is Dictionary) else a[1]
			return _ok(null)
		"deal_damage":
			return _deal_damage(e, a)
		"heal":
			var amt: Variant = _amount(a[1], "heal")
			if amt is String:
				return _fail(amt)
			var cover_h := _cover("heal", "max_heal", float(amt))
			if cover_h != "":
				return _fail(cover_h)
			if not e.alive:
				eng.emit(EventTypes.TARGET_SKIPPED, ctx.actor.id, e.id, {"reason": "dead"}, ctx.cause_id)
				return _ok(false, 2)
			eng.direct_heal(ctx.actor, e, float(amt), "script", ctx.cause_id)
			return _ok(true, 2)
		"modify_resource":
			var d: Variant = _amount(a[2], "modify_resource", true)
			if d is String:
				return _fail(d)
			var rs: ResourceState = e.get_resource(str(a[1]))
			if rs == null or not e.alive:
				eng.emit(EventTypes.TARGET_SKIPPED, ctx.actor.id, e.id, {"reason": "sin_recurso:" + str(a[1])}, ctx.cause_id)
				return _ok(false, 2)
			eng.change_resource(e, rs.id, float(d), "script", ctx.cause_id)
			return _ok(true, 2)
		"apply_status":
			return _apply_status(e, a)
		"remove_status":
			if not (a[1] is String):
				return _fail("remove_status: el estado debe ser texto")
			var removed := eng.status_service.dispel(e, {"status": a[1], "force": false}, "dispelled", ctx.cause_id)
			return _ok(float(removed.size()), 2)
		"emit":
			var nm := str(a[0])
			if not (a[0] is String) or not RegEx.create_from_string("^[a-z][a-z0-9_]{0,31}$").search(nm):
				return _fail("emit: el nombre debe ser un identificador en minusculas")
			var data: Dictionary = {}
			if a.size() > 1:
				if not (a[1] is Dictionary) or (a[1] as Dictionary).size() > 16:
					return _fail("emit: los datos deben ser un mapa de hasta 16 claves")
				for k in a[1]:
					var v: Variant = a[1][k]
					if not (v is float or v is String or v is bool):
						return _fail("emit: el dato '%s' debe ser numero, texto o booleano" % str(k))
				data = (a[1] as Dictionary).duplicate()
			eng.emit("user." + nm, ctx.actor.id, "", data, ctx.cause_id)
			return _ok(null, 2)
		"metric":
			var mn := str(a[0])
			if not (a[0] is String) or not RegEx.create_from_string("^[a-z][a-z0-9_]{0,31}$").search(mn):
				return _fail("metric: el nombre debe ser un identificador en minusculas")
			var mv: Variant = _amount(a[1], "metric", true)
			if mv is String:
				return _fail(mv)
			eng.add_metric(mn, ctx.actor.id, float(mv))
			return _ok(null, 1)
		"attack_roll":
			var roll := eng.roll_attack(ctx.actor, e, false, false, 0.0, ctx.cause_id)
			return _ok(bool(roll["hit"]), 2)
		"rand":
			return _ok(eng.rng.stream(_rng_stream).next_float())
		"rand_int":
			if not (a[0] is float) or a[0] < 1.0 or a[0] > 1000000.0:
				return _fail("rand_int: n debe estar entre 1 y 1000000")
			return _ok(float(eng.rng.stream(_rng_stream).next_int(int(a[0]))))
		"chance":
			if not (a[0] is float):
				return _fail("chance: p debe ser un numero")
			return _ok(eng.rng.stream(_rng_stream).next_float() < clampf(a[0], 0.0, 1.0))
	return _fail("funcion de API sin implementar '%s'" % name)


## Hace cumplir el contrato mecanico (tope acumulado por ejecucion). "" si cabe.
func _cover(call: String, key: String, amount: float) -> String:
	if contract == null:
		return ""
	var cap := float((contract as Dictionary).get(key, 0.0))
	var used := damage_used if key == "max_damage" else heal_used
	if used + amount > cap + 1e-9:
		return "[contrato] `%s` supera el tope %s=%s del contrato (acumulado %s + %s)" % [call, key, str(cap), str(used), str(amount)]
	if key == "max_damage":
		damage_used += amount
	else:
		heal_used += amount
	return ""


## Numero finito dentro de limites razonables, o texto de error.
func _amount(v: Variant, what: String, allow_negative: bool = false) -> Variant:
	if not (v is float):
		return "%s: la cantidad debe ser un numero" % what
	if absf(v) > 1.0e9:
		return "%s: cantidad fuera de rango" % what
	if v < 0.0 and not allow_negative:
		return "%s: la cantidad no puede ser negativa" % what
	return v


func _deal_damage(target: CombatEntity, a: Array) -> Dictionary:
	var eng := ctx.engine
	var amt: Variant = _amount(a[1], "deal_damage")
	if amt is String:
		return _fail(amt)
	var opts: Dictionary = {}
	if a.size() > 2:
		if not (a[2] is Dictionary):
			return _fail("deal_damage: las opciones deben ser un mapa")
		opts = a[2]
	for k in opts:
		if not ["damage_type", "element", "pen_pct", "pen_flat", "elem_pen", "crit"].has(str(k)):
			return _fail("deal_damage: opcion desconocida '%s'" % str(k))
	var dtype := str(opts.get("damage_type", "physical"))
	if not AbilityDef.DAMAGE_TYPES.has(dtype):
		return _fail("deal_damage: damage_type invalido '%s'" % dtype)
	var element := str(opts.get("element", ""))
	if element != "" and not (eng.rules.get_path_value("elements") as Array).has(element):
		return _fail("deal_damage: elemento '%s' fuera del catalogo del reglamento" % element)
	for nk in ["pen_pct", "pen_flat", "elem_pen"]:
		if opts.has(nk) and not (opts[nk] is float):
			return _fail("deal_damage.%s debe ser un numero" % nk)
	if opts.has("crit") and not (opts["crit"] is bool):
		return _fail("deal_damage.crit debe ser booleano")
	var cover_d := _cover("deal_damage", "max_damage", float(amt))
	if cover_d != "":
		return _fail(cover_d)
	if not target.alive:
		eng.emit(EventTypes.TARGET_SKIPPED, ctx.actor.id, target.id, {"reason": "dead"}, ctx.cause_id)
		return _ok(0.0, 2)
	var comp := {"damage_type": dtype, "element": element, "pen_pct": float(opts.get("pen_pct", 0.0)), "pen_flat": float(opts.get("pen_flat", 0.0)), "elem_pen": float(opts.get("elem_pen", 0.0))}
	var calc := DamageCalculator.compute(eng.rules, ctx.actor, target, comp, float(amt), bool(opts.get("crit", false)))
	eng.deliver_damage(ctx.actor, target, {
		"component": mutations - 1, "damage_type": dtype, "element": element, "crit": bool(opts.get("crit", false)),
		"base": calc["base"], "premitigation": calc["premitigation"], "defense_used": calc["defense_used"],
		"resistance_used": calc["resistance_used"], "amount": calc["amount"],
	}, ctx.cause_id)
	return _ok(calc["amount"], 2)


func _apply_status(target: CombatEntity, a: Array) -> Dictionary:
	var eng := ctx.engine
	if not (a[1] is String) or not eng.catalog.has(a[1]):
		return _fail("apply_status: estado desconocido '%s'" % str(a[1]))
	var opts: Dictionary = {}
	if a.size() > 2:
		if not (a[2] is Dictionary):
			return _fail("apply_status: las opciones deben ser un mapa")
		opts = a[2]
	for k in opts:
		if not ["stacks", "duration", "magnitude"].has(str(k)) or not (opts[k] is float):
			return _fail("apply_status: opcion invalida '%s' (stacks, duration, magnitude numericos)" % str(k))
	var o := {"stacks": int(opts.get("stacks", 1.0)), "magnitude": float(opts.get("magnitude", 1.0)), "cause": ctx.cause_id}
	if o["stacks"] < 1 or o["stacks"] > 99:
		return _fail("apply_status.stacks debe estar entre 1 y 99")
	if opts.has("duration"):
		if float(opts["duration"]) < 1.0 or float(opts["duration"]) > 1000.0:
			return _fail("apply_status.duration debe estar entre 1 y 1000")
		o["duration"] = float(opts["duration"])
	eng.status_service.apply(a[1], target, ctx.actor, o)
	return _ok(true, 3)
