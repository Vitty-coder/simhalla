class_name BalanceEvaluator
extends RefCounted
## Valoracion AUTOMATICA y trazable del coste de creacion de un PJ segun un perfil de equilibrio.
##
## Los PC solo regulan la construccion (independientes de los costes de uso en combate). El calculo sale
## exclusivamente de las reglas del perfil (CostRules) aplicadas a hechos extraidos del contenido: el creador
## no puede aportar costes (los datos con campos desconocidos se rechazan al construir la entidad).
##
## Contrato (PROJECT.md 9.2): creation_cost = estadisticas + componentes comprados + otros costes - creditos.
##  - Estadisticas base: gratis. Por encima/debajo del perfil: coste/credito (credit_factor).
##  - Habilidades: suma de operaciones x restricciones (cooldown, coste, usos, requisitos, disparadores...) segun
##    la formula de habilidad del perfil. Pasivas y modificadores del artefacto: como ajustes de estadistica.
##  - Estados: la definicion se cobra UNA vez por entidad aunque la referencien varias operaciones (cada
##    aplicacion paga solo su parte); invocaciones: la plantilla se valora como un PJ y cada operacion paga por instancia.
##  - Desventajas: credito automatico por estadisticas por debajo de la base, modificadores negativos y dano
##    autoinfligido, con tope `credit_cap`. Nunca por declaraciones del autor.
##  - Ataque basico universal e IA: gratuitos (el perfil no puede cambiarlo). Sin recargo por sinergias (suma simple).
##  - Scripts: evaluables solo si no tienen poder mecanico, o si declaran un `contract` (max_damage/max_heal) que el
##    motor hace cumplir; el resto se marca NO EVALUABLE sin inventar un precio.
## Modo libre: valida lo tecnico y avisa de lo demas. Modo reglamentado: exige presupuesto y evaluabilidad.

const REFERENCE_TEAM_SIZE := 3 ## equipo de referencia para selectores `all_*` (supuesto documentado)
const MODES := ["free", "regulated"]
const MAX_DEPTH := 3

var profile: BalanceProfile
var rules: Ruleset
var registry: OperationRegistry
var report: BalanceReport = BalanceReport.new()

var _entity: CombatEntity = null
var _ref: CombatEntity = null
var _natives: Dictionary = {}
var _custom_statuses: Dictionary = {}
var _status_queue: Array = []
var _status_done: Dictionary = {}
var _resources: Dictionary = {} ## recursos del dueno actual (para el coste relativo)
var _fake_status: StatusInstance = StatusInstance.new()
var _depth: int = 0
var _template_cache: Dictionary = {}


## Valora `data` (el mismo diccionario de entidad que EntityFactory). options: {mode, budget, depth}.
static func evaluate(data: Dictionary, prof: BalanceProfile, ruleset: Ruleset, reg: OperationRegistry, options: Dictionary = {}) -> BalanceReport:
	var ev := BalanceEvaluator.new()
	ev.profile = prof
	ev.rules = ruleset
	ev.registry = reg
	ev._depth = int(options.get("depth", 0))
	return ev._run(data, options)


func _run(data: Dictionary, options: Dictionary) -> BalanceReport:
	var r := report
	r.entity_id = str(data.get("id", "?"))
	r.profile_id = profile.id
	r.profile_version = profile.version
	r.illustrative = profile.illustrative
	r.mode = str(options.get("mode", "free"))
	if not MODES.has(r.mode):
		r.technical_errors.append("modo desconocido '%s' (use: %s)" % [r.mode, ", ".join(MODES)])
		return r
	var bid := str(options.get("budget", profile.default_budget))
	if bid != "":
		if not profile.budgets.has(bid):
			r.technical_errors.append("presupuesto desconocido '%s' (perfil: %s)" % [bid, ", ".join(profile.budgets.keys())])
			return r
		r.budget_id = bid
		r.budget_points = float(profile.budgets[bid]["points"])
	if not profile.is_valid():
		r.technical_errors = ["perfil de equilibrio invalido: " + "; ".join(profile.errors)]
		return r
	# 1. validez tecnica: la entidad debe construirse (esquema, referencias, formulas, scripts seguros)
	var built := EntityFactory.build(data, profile, rules, registry)
	if not built["errors"].is_empty():
		r.technical_errors = built["errors"]
		return r
	_entity = built["entity"]
	# ensayo en un motor real (referencias a estados/plantillas, catalogo elemental...): validez tecnica completa
	var probe: CombatEntity = EntityFactory.build({"id": "probe_enemy", "team": "probe", "ai": {"type": "passive"}, "basic_attack": false}, profile, rules, registry)["entity"]
	var original_team := _entity.team
	_entity.team = "probe_a"
	var setup_errs := CombatEngine.new().setup(rules, [_entity, probe], 1)
	_entity.team = original_team
	if not setup_errs.is_empty():
		r.technical_errors = setup_errs
		return r
	_ref = EntityFactory.build({"id": "ref_target", "team": "ref", "basic_attack": false, "ai": {"type": "passive"}}, profile, rules, registry)["entity"]
	_fake_status.stacks = 1
	_fake_status.magnitude = 1.0
	_load_statuses(data)
	if not profile.has_costs():
		_note_unevaluable("profile", "el perfil '%s' no define modelo de costes" % profile.id)
	else:
		_price_entity(data)
	_finish()
	return r


# --- Items ---------------------------------------------------------------------------------------------

func _round(v: float) -> float:
	return Rounding.apply(v, str(profile.rounding["mode"]), int(profile.rounding["decimals"]))


func _add(kind: String, id: String, origin: String, rule: String, amount: float, facts: Dictionary = {}, formula: String = "", counted: bool = true, parent: String = "") -> Dictionary:
	var it := {"id": id, "kind": kind, "origin": origin, "rule": rule, "parent": parent, "counted": counted, "credit": amount < 0.0,
		"amount": _round(amount), "facts": facts, "formula": formula, "unevaluable": false, "reason": ""}
	report.items.append(it)
	return it


func _note_unevaluable(id: String, reason: String, kind: String = "component", origin: String = "character", parent: String = "") -> void:
	report.unevaluable.append({"id": id, "reason": reason})
	var it := _add(kind, id, origin, "(sin regla)", 0.0, {}, "", false, parent)
	it["unevaluable"] = true
	it["reason"] = reason


func _rule_amount(rule: Dictionary, facts: Dictionary) -> Dictionary:
	return CostRules.evaluate(rule, facts)


func _load_statuses(data: Dictionary) -> void:
	var f := FileAccess.open(StatusCatalog.NATIVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if parsed is Dictionary:
		for d in parsed.get("statuses", []):
			_natives[str(d["id"])] = d
	for d in data.get("statuses", []):
		_custom_statuses[str(d.get("id", ""))] = d
	var art: Variant = data.get("artifact", null)
	if art is Dictionary:
		for d in art.get("statuses", []):
			_custom_statuses[str(d.get("id", ""))] = d


# --- Entidad -----------------------------------------------------------------------------------------------

func _price_entity(data: Dictionary) -> void:
	# estadisticas base: gratis; solo se cobra la diferencia con el perfil
	var st: Variant = data.get("stats", {})
	var names: Array = (st as Dictionary).keys() if st is Dictionary else []
	names.sort()
	for s in names:
		_price_stat(str(s), float(st[s]), "character", "stats.%s" % str(s))
	_resources = (data.get("resources", {}) as Dictionary) if data.get("resources", {}) is Dictionary else {}
	_price_resources(data.get("resources", {}), "character")
	var abilities: Array = data.get("abilities", [])
	for a in abilities:
		_price_ability(a, "character")
	var art: Variant = data.get("artifact", null)
	if art is Dictionary:
		var origin := "artifact:%s" % str(art.get("id", "?"))
		var saved := _resources
		var merged := _resources.duplicate()
		merged.merge(art.get("resources", {}) if art.get("resources", {}) is Dictionary else {})
		_resources = merged
		for m in art.get("modifiers", []):
			_price_modifier(m, origin, "artifact.modifiers", "", false)
		_price_resources(art.get("resources", {}), origin)
		for a in art.get("abilities", []):
			_price_ability(a, origin)
		_resources = saved
	if bool(data.get("basic_attack", true)):
		_add("basic_attack", "basic_attack", "character", "free.basic_attack", 0.0, {}, "", false)
	if data.has("ai") or art is Dictionary and (art as Dictionary).has("ai_rules"):
		_add("ai", "ai", "character", "free.ai", 0.0, {}, "", false)
	# definiciones de estado referenciadas: una vez cada una (puede referenciar mas estados)
	while not _status_queue.is_empty():
		var sid: String = _status_queue.pop_front()
		if not _status_done.has(sid):
			_status_done[sid] = true
			_price_status_def(sid)


func _finish() -> void:
	var r := report
	r.gross = 0.0
	r.credits_raw = 0.0
	for it in r.items:
		if bool(it["counted"]):
			if float(it["amount"]) < 0.0:
				r.credits_raw += -float(it["amount"])
			else:
				r.gross += float(it["amount"])
	r.credits_applied = r.credits_raw
	if profile.credit_cap.has("fraction_of_gross"):
		var cap := _round(r.gross * float(profile.credit_cap["fraction_of_gross"]))
		if r.credits_raw > cap:
			r.credits_applied = cap
			_add("credit_cap", "credit_cap", "profile", "credit_cap.fraction_of_gross", r.credits_raw - cap,
				{"credits_raw": r.credits_raw, "gross": r.gross, "fraction": profile.credit_cap["fraction_of_gross"]}, "", true)
	r.creation_cost = 0.0
	for it in r.items:
		if bool(it["counted"]):
			r.creation_cost += float(it["amount"])
	r.creation_cost = _round(r.creation_cost)
	r.remaining = r.budget_points - r.creation_cost if r.budget_points >= 0.0 else 0.0
	if profile.illustrative:
		r.warnings.append("perfil ilustrativo '%s': valoracion de PRUEBA, no un equilibrio definitivo" % profile.id)
	# comprobaciones segun el modo
	var findings: Array = []
	if not r.within_budget():
		findings.append("[presupuesto] el coste de creacion %s excede el presupuesto '%s' (%s PC)" % [BalanceReport._n(r.creation_cost), r.budget_id, BalanceReport._n(r.budget_points)])
	for u in r.unevaluable:
		findings.append("[no_evaluable] %s: %s" % [u["id"], u["reason"]])
	if r.budget_points < 0.0 and r.mode == "regulated":
		findings.append("[presupuesto] el modo reglamentado requiere un presupuesto (perfil sin default_budget y ninguno indicado)")
	if r.mode == "regulated":
		r.errors.append_array(findings)
	else:
		for f in findings:
			r.warnings.append("modo libre: %s" % f)


# --- Estadisticas ------------------------------------------------------------------------------------------

func _stat_rule(stat: String) -> Dictionary:
	var st: Dictionary = profile.costs.get("stats", {})
	var rules_d: Dictionary = st.get("rules", {})
	if rules_d.has(stat):
		return {"rule": rules_d[stat], "name": "stats.rules.%s" % stat}
	var best := ""
	for p in st.get("patterns", {}):
		var pre := str(p).trim_suffix("*")
		if stat.begins_with(pre) and pre.length() > best.length():
			best = str(p)
	if best != "":
		return {"rule": st["patterns"][best], "name": "stats.patterns.%s" % best}
	if profile.base_stats.has(stat):
		if st.has("default"):
			return {"rule": st["default"], "name": "stats.default"}
	elif st.has("custom"):
		return {"rule": st["custom"], "name": "stats.custom"}
	elif st.has("default"):
		return {}
	return {}


## Importe (con signo) de variar `stat` en `delta` respecto a su base. {"ok", "amount", "rule", "facts", "formula"}.
func _stat_amount(stat: String, delta: float, absolute: bool = false) -> Dictionary:
	var base: float = float(profile.base_stats.get(stat, 0.0))
	var found := _stat_rule(stat)
	if found.is_empty():
		return {"ok": false, "reason": "el perfil no tiene regla de coste para la estadistica '%s'" % stat}
	var d := absf(delta) if absolute else delta
	var facts := {"delta": d, "base": base, "value": base + d}
	var res := _rule_amount(found["rule"], facts)
	if not res["ok"]:
		return {"ok": false, "reason": "regla %s: %s" % [found["name"], res["error"]]}
	var amount: float = float(res["value"])
	if amount < 0.0:
		amount *= float(profile.costs.get("stats", {}).get("credit_factor", 1.0))
	return {"ok": true, "amount": amount, "rule": found["name"], "facts": facts, "formula": str(found["rule"]["formula"])}


func _price_stat(stat: String, value: float, origin: String, id: String) -> void:
	var base: float = float(profile.base_stats.get(stat, 0.0))
	var delta := value - base
	if is_zero_approx(delta):
		return # igual a la base del perfil: gratis
	var r := _stat_amount(stat, delta)
	if not bool(r["ok"]):
		_note_unevaluable(id, str(r["reason"]), "stat", origin)
		return
	_add("stat_credit" if float(r["amount"]) < 0.0 else "stat", id, origin, str(r["rule"]), float(r["amount"]), r["facts"], str(r["formula"]))


## `absolute`: en estados aplicados a otros, un modificador negativo es poder ofensivo (no desventaja propia).
func _price_modifier(m: Variant, origin: String, id_prefix: String, parent: String, absolute: bool, max_stacks: int = 1) -> float:
	if not (m is Dictionary):
		return 0.0
	var stat := str(m.get("stat", ""))
	var id := "%s:%s:%s" % [id_prefix, stat, str(m.get("kind", "flat"))]
	var v := float(m.get("value", 0.0)) + float(m.get("per_stack", 0.0)) * float(maxi(max_stacks - 1, 0))
	var base: float = float(profile.base_stats.get(stat, 0.0))
	var delta: float
	match str(m.get("kind", "flat")):
		"flat":
			delta = v
		"pct_add":
			delta = base * v
		"mult":
			delta = base * (v - 1.0)
		"set":
			delta = v - base
		_:
			_note_unevaluable(id, "los modificadores '%s' no se pueden valorar con el perfil" % str(m.get("kind", "")), "passive_modifier", origin, parent)
			return 0.0
	if is_zero_approx(delta):
		return 0.0
	var r := _stat_amount(stat, delta, absolute)
	if not bool(r["ok"]):
		_note_unevaluable(id, str(r["reason"]), "passive_modifier", origin, parent)
		return 0.0
	var amount: float = float(r["amount"])
	_add("modifier_credit" if amount < 0.0 else "passive_modifier", id, origin, str(r["rule"]), amount, r["facts"], str(r["formula"]), not absolute, parent)
	return amount


func _price_resources(res: Variant, origin: String) -> void:
	if not (res is Dictionary):
		return
	var ids: Array = (res as Dictionary).keys()
	ids.sort()
	for rid in ids:
		var d: Dictionary = res[rid]
		var rule: Variant = profile.costs.get("resource", null)
		var id := "resource:%s" % str(rid)
		if rule == null:
			_note_unevaluable(id, "el perfil no tiene regla de coste para recursos", "resource", origin)
			continue
		var initial := float(d.get("initial", d.get("max", 0.0)))
		var mx := float(d["max"]) if d.has("max") else initial
		var facts := {"initial": initial, "max": mx, "min": float(d.get("min", 0.0)), "regen": float(d.get("regen_per_turn", 0.0))}
		var res_a := _rule_amount(rule, facts)
		if not res_a["ok"]:
			_note_unevaluable(id, "regla resource: %s" % res_a["error"], "resource", origin)
			continue
		_add("resource", id, origin, "resource", maxf(float(res_a["value"]), 0.0), facts, str(rule["formula"]))


# --- Habilidades -------------------------------------------------------------------------------------------

func _num_of(v: Variant, fallback: float = 0.0) -> float:
	if v is float or v is int:
		return float(v)
	if v is Dictionary:
		return float(v.get("amount", fallback))
	return fallback


func _price_ability(a: Variant, origin: String) -> float:
	if not (a is Dictionary):
		return 0.0
	var aid := str(a.get("id", "?"))
	var id := "ability:%s" % aid
	var parent := id
	var ctx := {"target_count": float(maxi(int(a.get("target_count", 1)), 1)), "ability": aid, "origin": origin}
	# pasivas: modificadores como ajustes de estadistica (credito si son negativos)
	var passive: Variant = a.get("passive", null)
	if passive is Dictionary:
		for m in passive.get("modifiers", []):
			_price_modifier(m, origin, "%s/passive" % id, parent, false)
	var effects_sum := 0.0
	var any_effect := false
	var ok_all := true
	var effs: Array = a.get("effects", [])
	for i in effs.size():
		any_effect = true
		var r := _price_effect(effs[i], ctx, "%s/effects[%d]" % [id, i], parent, origin)
		effects_sum += float(r["raw"])
		ok_all = ok_all and bool(r["ok"])
	var rule: Variant = profile.costs.get("ability", null)
	var cost := effects_sum
	var facts := {}
	var formula := ""
	var rule_name := "ability(sin regla: suma de efectos)"
	if rule != null:
		facts = _ability_facts(a, effects_sum, any_effect, ctx)
		var res := _rule_amount(rule, facts)
		if not res["ok"]:
			_note_unevaluable(id, "regla ability: %s" % res["error"], "ability", origin)
			return 0.0
		cost = maxf(float(res["value"]), float((rule as Dictionary).get("min", 0.0)) if any_effect else 0.0)
		formula = str(rule["formula"])
		rule_name = "ability"
	var it := _add("ability", id, origin, rule_name, cost, facts, formula, true)
	if not ok_all:
		it["reason"] = "incluye componentes no evaluables (sin precio); ver `unevaluable`"
	return cost


func _ability_facts(a: Dictionary, effects_sum: float, any_effect: bool, ctx: Dictionary) -> Dictionary:
	var cost: Dictionary = a.get("cost", {}) if a.get("cost", {}) is Dictionary else {}
	var total := 0.0
	var ratio := 0.0
	for rid in cost:
		total += float(cost[rid])
		var rd: Variant = _resources.get(rid, {})
		var cap := 1.0
		if rd is Dictionary:
			cap = float(rd.get("max", rd.get("initial", 1.0)))
		ratio += clampf(float(cost[rid]) / maxf(cap, 1.0), 0.0, 1.0)
	if not cost.is_empty():
		ratio /= float(cost.size())
	var trig: Dictionary = a.get("trigger", {}) if a.get("trigger", {}) is Dictionary else {}
	var charges: Dictionary = a.get("charges", {}) if a.get("charges", {}) is Dictionary else {}
	var upc := float(a.get("uses_per_combat", 0))
	var upt := float(a.get("uses_per_turn", 0))
	return {
		"effects": effects_sum, "has_effects": 1.0 if any_effect else 0.0, "cooldown": _num_of(a.get("cooldown", 0.0)),
		"resource_cost": total, "resource_cost_ratio": ratio, "limited": 1.0 if (upc > 0.0 or upt > 0.0 or not charges.is_empty()) else 0.0,
		"uses_per_combat": upc, "uses_per_turn": upt, "charges": float(charges.get("max", 0.0)), "cast_time": float(a.get("cast_time", 0.0)),
		"requires": float((a.get("requires", {}) as Dictionary).size()) if a.get("requires", {}) is Dictionary else 0.0,
		"is_free": 1.0 if str(a.get("action_type", "main")) == "free" else 0.0,
		"is_reaction": 1.0 if str(a.get("action_type", "main")) == "reaction" else 0.0,
		"is_triggered": 1.0 if not trig.is_empty() else 0.0, "trigger_chance": float(trig.get("chance", 1.0)),
		"trigger_limit": float(trig.get("limit_per_turn", 0.0)), "target_count": float(ctx["target_count"]),
	}


# --- Efectos -----------------------------------------------------------------------------------------------

func _eval_formula(text: String) -> Dictionary:
	var f := Formula.parse(text)
	return f.evaluate(FormulaContext.new(_entity, _ref, _fake_status).resolver())


func _targets_of(e: Dictionary, ctx: Dictionary) -> float:
	match str(e.get("on", "targets")):
		"caster", "random_enemy", "random_ally", "lowest_hp_enemy":
			return 1.0
		"all_enemies", "all_allies":
			return float(REFERENCE_TEAM_SIZE)
	return float(ctx["target_count"])


## Valora un efecto. Devuelve {"raw": coste evaluable, "ok": bool}. Anade items informativos (no contados).
func _price_effect(e: Variant, ctx: Dictionary, id: String, parent: String, origin: String, depth: int = 0) -> Dictionary:
	if not (e is Dictionary):
		return {"raw": 0.0, "ok": true}
	var type := str(e.get("type", ""))
	var free_ops: Array = profile.costs.get("free", {}).get("operations", ["emit_event", "metric"])
	if free_ops.has(type) or (type == "emit_event" or type == "metric"):
		_add("operation", id, origin, "free.operations", 0.0, {"type": type}, "", false, parent)
		return {"raw": 0.0, "ok": true}
	if type == "script":
		return _price_script(e, ctx, id, parent, origin)
	var ops: Dictionary = profile.costs.get("operations", {})
	if not ops.has(type):
		_note_unevaluable(id, "el perfil no tiene regla de coste para la operacion '%s'" % type, "operation", origin, parent)
		return {"raw": 0.0, "ok": false}
	var facts_r := _op_facts(type, e, ctx, depth)
	if not bool(facts_r["ok"]):
		_note_unevaluable(id, str(facts_r["reason"]), "operation", origin, parent)
		return {"raw": 0.0, "ok": false}
	var facts: Dictionary = facts_r["facts"]
	# dano autoinfligido = desventaja: credito automatico (nunca precio positivo)
	if type == "damage" and float(facts["on_caster"]) > 0.0:
		var wk: Variant = profile.costs.get("weaknesses", {}).get("self_damage", null)
		if wk == null:
			_note_unevaluable(id, "dano autoinfligido sin regla de debilidad en el perfil", "operation", origin, parent)
			return {"raw": 0.0, "ok": false}
		var wr := _rule_amount(wk, {"power": facts["power"]})
		if not wr["ok"]:
			_note_unevaluable(id, "regla weaknesses.self_damage: %s" % wr["error"], "operation", origin, parent)
			return {"raw": 0.0, "ok": false}
		_add("weakness", id, origin, "weaknesses.self_damage", -maxf(float(wr["value"]), 0.0), {"power": facts["power"]}, str(wk["formula"]), true, parent)
		return {"raw": 0.0, "ok": true}
	var rule: Dictionary = ops[type]
	var res := _rule_amount(rule, facts)
	if not res["ok"]:
		_note_unevaluable(id, "regla operations.%s: %s" % [type, res["error"]], "operation", origin, parent)
		return {"raw": 0.0, "ok": false}
	var amount := maxf(float(res["value"]), 0.0)
	_add("operation", id, origin, "operations.%s" % type, amount, facts, str(rule["formula"]), false, parent)
	return {"raw": amount, "ok": true}


func _duration_of(spec: Variant, fallback: float) -> float:
	if spec is Dictionary:
		if str(spec.get("unit", "")) == "permanent":
			return 999.0
		return float(spec.get("amount", fallback))
	if spec is float or spec is int:
		return float(spec)
	return fallback


func _op_facts(type: String, e: Dictionary, ctx: Dictionary, depth: int) -> Dictionary:
	var facts := {"chance": float(e.get("chance", 1.0)), "targets": _targets_of(e, ctx), "on_caster": 1.0 if str(e.get("on", "targets")) == "caster" else 0.0}
	match type:
		"damage":
			var power := 0.0
			var true_p := 0.0
			var pen_pct := 0.0
			var pen_flat := 0.0
			var elem_pen := 0.0
			var comps: Array = e.get("components", [])
			for c in comps:
				var r := _eval_formula(str(c.get("formula", "0")))
				if not r["ok"]:
					return {"ok": false, "reason": "formula de dano no valorable: %s" % r["error"]}
				var v := maxf(float(r["value"]), 0.0)
				var el := str(c.get("element", ""))
				if el != "":
					v *= maxf(1.0 + _entity.stats.get_value("ELEM_AFF." + el), 0.0)
				power += v
				if str(c.get("damage_type", "")) == "true":
					true_p += v
				pen_pct = maxf(pen_pct, float(c.get("pen_pct", 0.0)))
				pen_flat = maxf(pen_flat, float(c.get("pen_flat", 0.0)))
				elem_pen = maxf(elem_pen, float(c.get("elem_pen", 0.0)))
			facts.merge({"power": power, "components": float(comps.size()), "pen_pct": pen_pct, "pen_flat": pen_flat, "elem_pen": elem_pen,
				"always_hit": 1.0 if bool(e.get("always_hit", false)) else 0.0, "can_crit": 1.0 if bool(e.get("can_crit", true)) else 0.0,
				"crit_bonus": float(e.get("crit_bonus", 0.0)), "true_share": (true_p / power) if power > 0.0 else 0.0})
		"heal":
			var r2 := _eval_formula(str(e.get("formula", "0")))
			if not r2["ok"]:
				return {"ok": false, "reason": "formula de curacion no valorable: %s" % r2["error"]}
			facts.merge({"power": maxf(float(r2["value"]), 0.0), "can_crit": 1.0 if bool(e.get("can_crit", false)) else 0.0})
		"apply_status":
			var sid := str(e.get("status", ""))
			var def: Dictionary = _custom_statuses.get(sid, _natives.get(sid, {}))
			var mag := 1.0
			if e.has("magnitude"):
				if e["magnitude"] is String:
					var rm := _eval_formula(str(e["magnitude"]))
					if not rm["ok"]:
						return {"ok": false, "reason": "magnitud no valorable: %s" % rm["error"]}
					mag = float(rm["value"])
				else:
					mag = float(e["magnitude"])
			facts.merge({"stacks": float(e.get("stacks", 1)), "duration": _duration_of(e.get("duration", def.get("duration", 3)), 3.0), "magnitude": mag})
			if not _status_done.has(sid) and not _status_queue.has(sid):
				_status_queue.append(sid)
		"remove_status":
			facts.merge({"count": float(e.get("count", 1)), "force": 1.0 if bool(e.get("force", false)) else 0.0, "by_tags": 1.0 if e.has("tags") or e.has("beneficial") else 0.0})
		"extend_status":
			facts.merge({"amount": float(e.get("amount", 0.0))})
		"transfer_status":
			facts.merge({"count": float(e.get("count", 1)), "steal": 1.0 if str(e.get("mode", "")) == "steal" else 0.0, "give": 1.0 if str(e.get("mode", "")) == "give" else 0.0})
		"invert_status", "propagate_status":
			facts.merge({"count": float(e.get("count", 1))})
		"modify_resource":
			var amt := 0.0
			if e.get("amount", 0.0) is String:
				var ra := _eval_formula(str(e["amount"]))
				if not ra["ok"]:
					return {"ok": false, "reason": "cantidad no valorable: %s" % ra["error"]}
				amt = float(ra["value"])
			else:
				amt = float(e.get("amount", 0.0))
			facts.merge({"amount": amt, "is_max": 1.0 if str(e.get("property", "value")) == "max" else 0.0, "is_set": 1.0 if str(e.get("mode", "add")) == "set" else 0.0})
		"modify_initiative":
			var ia := 0.0
			if e.get("amount", 0.0) is String:
				var ri := _eval_formula(str(e["amount"]))
				if not ri["ok"]:
					return {"ok": false, "reason": "cantidad no valorable: %s" % ri["error"]}
				ia = float(ri["value"])
			else:
				ia = float(e.get("amount", 0.0))
			facts.merge({"amount": ia, "extra_turn": 1.0 if str(e.get("mode", "")) == "extra_turn" else 0.0, "steal": 1.0 if str(e.get("mode", "")) == "steal" else 0.0})
		"modify_cooldown":
			facts.merge({"amount": float(e.get("amount", 0.0)), "reset": 1.0 if str(e.get("mode", "")) == "reset" else 0.0, "all": 0.0 if e.has("ability") else 1.0})
		"summon":
			var tn := str(e.get("template", ""))
			var tc := _template_cost(tn)
			if not bool(tc["ok"]):
				return {"ok": false, "reason": str(tc["reason"])}
			var inh := 0.0
			for k in (e.get("inherit", {}) as Dictionary).get("stat_pct", {}):
				inh += float(e["inherit"]["stat_pct"][k])
			facts.merge({"count": float(e.get("count", 1)), "lifespan": _duration_of(e.get("lifespan", 0.0), 0.0), "template_cost": float(tc["cost"]), "inherit_pct": inh})
		"record_state":
			facts.merge({"what_count": float((e.get("what", []) as Array).size())})
		"restore_state":
			facts.merge({"what_count": float((e.get("what", []) as Array).size()), "consume": 1.0 if bool(e.get("consume", true)) else 0.0})
		"delayed_effect":
			if depth >= 2:
				return {"ok": false, "reason": "efectos retrasados anidados"}
			var inner := 0.0
			var inner_effs: Array = e.get("effects", [])
			for j in inner_effs.size():
				var ri2 := _price_effect(inner_effs[j], ctx, "%s/inner[%d]" % [str(e.get("type")), j], "", str(ctx["origin"]), depth + 1)
				if not bool(ri2["ok"]):
					return {"ok": false, "reason": "contiene efectos no evaluables"}
				inner += float(ri2["raw"])
			facts.merge({"delay": float(e.get("delay", 0.0)), "inner": inner})
		"repeat_action":
			facts.merge({"times": float(e.get("times", 1))})
	return {"ok": true, "facts": facts}


## Coste de una plantilla de invocacion: se valora como un PJ completo (cacheado por plantilla).
func _template_cost(name: String) -> Dictionary:
	if _template_cache.has(name):
		return _template_cache[name]
	var tmpl: Variant = _entity.summon_templates.get(name, null)
	if tmpl == null:
		return {"ok": false, "reason": "plantilla de invocacion desconocida '%s'" % name}
	if _depth + 1 >= MAX_DEPTH:
		return {"ok": false, "reason": "plantillas de invocacion anidadas demasiado profundas"}
	var d: Dictionary = (tmpl as Dictionary).duplicate(true)
	d["id"] = "template_%s" % name
	d["team"] = "tmpl"
	var sub := BalanceEvaluator.evaluate(d, profile, rules, registry, {"mode": "free", "budget": "", "depth": _depth + 1})
	var out: Dictionary
	if not sub.technical_errors.is_empty():
		out = {"ok": false, "reason": "plantilla '%s' invalida: %s" % [name, str(sub.technical_errors[0])]}
	elif not sub.evaluable():
		out = {"ok": false, "reason": "plantilla '%s' con componentes no evaluables: %s" % [name, str(sub.unevaluable[0]["reason"])]}
	else:
		out = {"ok": true, "cost": sub.creation_cost}
	_template_cache[name] = out
	if bool(out["ok"]):
		_add("summon_template", "summon_template:%s" % name, "character", "(plantilla valorada como PJ)", sub.creation_cost, {"items": sub.items.size()}, "", false)
	return out


# --- Estados -----------------------------------------------------------------------------------------------

func _price_status_def(sid: String) -> void:
	var d: Variant = _custom_statuses.get(sid, _natives.get(sid, null))
	var id := "status:%s" % sid
	var origin := "custom" if _custom_statuses.has(sid) else "native"
	if d == null:
		_note_unevaluable(id, "estado desconocido '%s'" % sid, "status_def", origin)
		return
	var rule: Variant = profile.costs.get("status_def", null)
	if rule == null:
		_note_unevaluable(id, "el perfil no tiene regla de coste para definiciones de estado", "status_def", origin)
		return
	var ctx := {"target_count": 1.0, "ability": id, "origin": origin}
	var inner := 0.0
	var ok_all := true
	var max_stacks := int(d.get("stacking", {}).get("max_stacks", 1)) if d.get("stacking", {}) is Dictionary else 1
	for m in d.get("modifiers", []):
		inner += maxf(_price_modifier(m, origin, id + "/mod", id, true, max_stacks), 0.0)
	var blocks: Array = []
	for p in d.get("periodic", []):
		if p is Dictionary:
			blocks.append_array(p.get("effects", []))
	for key in ["on_apply", "on_expire", "on_death"]:
		blocks.append_array(d.get(key, []))
	for i in blocks.size():
		var r := _price_effect(blocks[i], ctx, "%s/effects[%d]" % [id, i], id, origin)
		inner += float(r["raw"])
		ok_all = ok_all and bool(r["ok"])
	var form: Dictionary = d.get("form", {}) if d.get("form", {}) is Dictionary else {}
	for a in form.get("add_abilities", []):
		inner += _price_ability(a, origin)
	var flags := 0.0
	for k in (d.get("flags", {}) as Dictionary):
		var fv: Variant = d["flags"][k]
		if (fv is bool and fv) or ((fv is float or fv is int) and float(fv) != 0.0) or ((fv is Array or fv is String or fv is Dictionary) and not fv.is_empty()):
			flags += 1.0
	var facts := {"inner": inner, "modifiers": float((d.get("modifiers", []) as Array).size()), "flags": flags,
		"defense": float((d.get("defense", {}) as Dictionary).size()), "periodic": float((d.get("periodic", []) as Array).size()),
		"has_form": 1.0 if not form.is_empty() else 0.0, "max_stacks": float(max_stacks), "beneficial": 1.0 if bool(d.get("beneficial", false)) else 0.0}
	var res := _rule_amount(rule, facts)
	if not res["ok"]:
		_note_unevaluable(id, "regla status_def: %s" % res["error"], "status_def", origin)
		return
	var it := _add("status_def", id, origin, "status_def", maxf(float(res["value"]), 0.0), facts, str(rule["formula"]), true)
	if not ok_all:
		it["reason"] = "incluye componentes no evaluables (sin precio); ver `unevaluable`"


# --- Scripts -----------------------------------------------------------------------------------------------

const POWER_CALLS := ["deal_damage", "heal", "apply_status", "remove_status", "modify_resource"]


func _price_script(e: Dictionary, ctx: Dictionary, id: String, parent: String, origin: String) -> Dictionary:
	var sid := str(e.get("script", ""))
	var prog: ScriptProgram = _entity.scripts.get(sid, null)
	if prog == null:
		_note_unevaluable(id, "script '%s' no disponible" % sid, "script", origin, parent)
		return {"raw": 0.0, "ok": false}
	var calls: Array = prog.reachable_calls(ScriptApi.EFFECT)
	var power_calls: Array = calls.filter(func(c): return POWER_CALLS.has(c))
	if power_calls.is_empty():
		_add("script", id, origin, "script.sin_poder_mecanico", 0.0, {"calls": calls, "hash": prog.source_hash.substr(0, 16)}, "", false, parent)
		return {"raw": 0.0, "ok": true}
	var contract: Variant = e.get("contract", null)
	if not (contract is Dictionary):
		_note_unevaluable(id, "script con poder mecanico (%s) y sin `contract` verificable: no evaluable, sin precio" % ", ".join(power_calls), "script", origin, parent)
		return {"raw": 0.0, "ok": false}
	var raw := 0.0
	for c in power_calls:
		var syn: Dictionary
		var op: String
		match c:
			"deal_damage":
				op = "damage"
				if not contract.has("max_damage"):
					_note_unevaluable(id, "contrato incompleto: usa deal_damage sin max_damage", "script", origin, parent)
					return {"raw": 0.0, "ok": false}
				# peor caso verificable: siempre impacta, puede critico y penetra toda la defensa
				syn = {"type": "damage", "always_hit": true, "can_crit": true, "on": "targets"}
				syn["_power"] = float(contract["max_damage"])
			"heal":
				op = "heal"
				if not contract.has("max_heal"):
					_note_unevaluable(id, "contrato incompleto: usa heal sin max_heal", "script", origin, parent)
					return {"raw": 0.0, "ok": false}
				syn = {"type": "heal", "can_crit": true, "on": "targets"}
				syn["_power"] = float(contract["max_heal"])
			_:
				_note_unevaluable(id, "el contrato no cubre `%s`: no evaluable, sin precio" % c, "script", origin, parent)
				return {"raw": 0.0, "ok": false}
		var ops: Dictionary = profile.costs.get("operations", {})
		if not ops.has(op):
			_note_unevaluable(id, "el perfil no tiene regla de coste para '%s' (necesaria para el contrato)" % op, "script", origin, parent)
			return {"raw": 0.0, "ok": false}
		var facts := {"chance": 1.0, "targets": 1.0, "on_caster": 0.0, "power": float(syn["_power"])}
		if op == "damage":
			facts.merge({"components": 1.0, "pen_pct": 1.0, "pen_flat": 0.0, "elem_pen": 0.0, "always_hit": 1.0, "can_crit": 1.0, "crit_bonus": 0.0, "true_share": 0.0})
		else:
			facts["can_crit"] = 1.0
		var res := _rule_amount(ops[op], facts)
		if not res["ok"]:
			_note_unevaluable(id, "regla operations.%s: %s" % [op, res["error"]], "script", origin, parent)
			return {"raw": 0.0, "ok": false}
		var amt := maxf(float(res["value"]), 0.0)
		_add("script_contract", "%s/%s" % [id, c], origin, "operations.%s (contrato, peor caso)" % op, amt, facts, str(ops[op]["formula"]), false, parent)
		raw += amt
	return {"raw": raw, "ok": true}
