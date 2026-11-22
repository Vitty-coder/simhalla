extends Phase3Case
## Fase 6: perfiles de equilibrio, valoracion automatica (PC) trazable, modos libre/reglamentado,
## contratos de script, integracion con importador y DuelRunner.

const REF := "res://content/balance/reference_costs.json"
const TMP := "user://_tests_phase6"


# --- utilidades --------------------------------------------------------------------------------------------

func _ref_dict() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(REF))


func _profile(mod: Callable = Callable()) -> BalanceProfile:
	var d := _ref_dict()
	if mod.is_valid():
		mod.call(d)
	return BalanceProfile.from_dict(d)


func _eval(extra: Dictionary = {}, opts: Dictionary = {}, prof: BalanceProfile = null) -> BalanceReport:
	var d := {"id": "hero", "team": "A", "basic_attack": false}
	d.merge(extra, true)
	return BalanceEvaluator.evaluate(d, prof if prof != null else _profile(), Ruleset.from_dict({}), OperationRegistry.new(), opts)


func _dmg(id: String, formula: String = "100", extra: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "targeting": "enemy", "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": formula}]}]}
	d.merge(extra, true)
	return d


func _item(r: BalanceReport, id: String) -> Dictionary:
	for it in r.items:
		if it["id"] == id:
			return it
	return {}


func _count(r: BalanceReport, id: String) -> int:
	return r.items.filter(func(it): return it["id"] == id).size()


func _cost(extra: Dictionary) -> float:
	var r := _eval(extra)
	assert_eq(r.technical_errors, [], "tecnico")
	return r.creation_cost


# --- perfil ----------------------------------------------------------------------------------------------------

func test_reference_profile_loads_and_matches_public_schema() -> void:
	var p := BalanceProfile.from_file(REF)
	assert_eq(p.errors, [])
	assert_true(p.has_costs())
	assert_true(p.illustrative, "el perfil de prueba esta marcado como ilustrativo")
	assert_eq(p.budgets.keys().size(), 4)
	assert_eq(p.default_budget, "standard")
	assert_eq(SchemaValidator.new().validate("balance.schema.json", _ref_dict()), [])
	var tech := BalanceProfile.from_file("res://content/balance/technical_profile.json")
	assert_eq(tech.errors, [])
	assert_false(tech.has_costs(), "el perfil tecnico no define costes")
	var bad := _ref_dict()
	bad["costs"]["operations"]["damage"]["formula"] = 5
	assert_true(SchemaValidator.new().validate("balance.schema.json", bad).size() > 0)


func test_invalid_profiles_are_rejected_with_clear_errors() -> void:
	var cases := {
		"clave desconocida": [func(d): d["precio_magico"] = 1, "propiedad desconocida"],
		"seccion de costes": [func(d): d["costs"]["magia"] = {}, "seccion desconocida"],
		"formula invalida": [func(d): d["costs"]["resource"]["formula"] = "max * (", "costs.resource.formula"],
		"hecho no disponible": [func(d): d["costs"]["resource"]["formula"] = "max + caster_hp", "hecho no disponible"],
		"hecho de otra regla": [func(d): d["costs"]["operations"]["heal"]["formula"] = "stacks * 2", "hecho no disponible"],
		"operacion sin modelo": [func(d): d["costs"]["operations"]["teleport"] = {"formula": "1"}, "sin modelo de coste"],
		"regla sin formula": [func(d): d["costs"]["resource"] = {"valor": 3}, "formula"],
		"IA con coste": [func(d): d["costs"]["free"]["ai"] = false, "IA de comportamiento es gratuita"],
		"ataque basico con coste": [func(d): d["costs"]["free"]["basic_attack"] = false, "ataque basico universal es gratuito"],
		"patron": [func(d): d["costs"]["stats"]["patterns"]["ELEM_RES"] = {"formula": "delta"}, "debe terminar en '*'"],
		"credit_factor": [func(d): d["costs"]["stats"]["credit_factor"] = 2, "credit_factor"],
		"presupuesto": [func(d): d["budgets"]["small"]["points"] = 0, "points"],
		"presupuesto por defecto": [func(d): d["default_budget"] = "nada", "default_budget"],
		"redondeo": [func(d): d["rounding"] = {"mode": "magico"}, "rounding"],
		"tope de creditos": [func(d): d["credit_cap"] = {"fraction_of_gross": 3}, "credit_cap"],
		"ability min": [func(d): d["costs"]["ability"]["min"] = "x", "min"],
	}
	for k in cases:
		var p := _profile(cases[k][0])
		assert_false(p.is_valid(), "debe rechazar: %s" % k)
		assert_contains(" ".join(p.errors), cases[k][1], k)
	# un perfil invalido no se usa para valorar: error tecnico, no precio inventado
	var r := _eval({}, {}, _profile(cases["formula invalida"][0]))
	assert_true(r.technical_errors.size() > 0)
	assert_false(r.valid())


func test_cost_formulas_use_the_safe_grammar_never_host_code() -> void:
	for evil in ["OS.execute(1)", "caster.ATK", "load(1)", "max_hp()", "1 ; 2"]:
		var p := _profile(func(d): d["costs"]["resource"]["formula"] = evil)
		assert_false(p.is_valid(), evil)


# --- estadisticas ------------------------------------------------------------------------------------------------

func test_base_stats_are_free_and_only_differences_are_charged() -> void:
	var base: Dictionary = _ref_dict()["base_stats"]
	assert_almost(_cost({"stats": base}), 0.0, 1e-9, "las estadisticas del perfil son gratis")
	assert_almost(_cost({}), 0.0)
	assert_almost(_cost({"stats": {"ATK": 150}}), 30.0, 1e-9, "+50 ATK x 0,6")
	var r := _eval({"stats": {"ATK": 150, "SPD": 110, "HP": 800}})
	assert_almost(_item(r, "stats.ATK")["amount"], 30.0)
	assert_almost(_item(r, "stats.SPD")["amount"], 8.0)
	assert_almost(_item(r, "stats.HP")["amount"], -5.0, 1e-9, "-200 HP x 0,05 x credit_factor 0,5")
	assert_true(_item(r, "stats.HP")["credit"])
	assert_eq(_item(r, "stats.HP")["kind"], "stat_credit")
	assert_almost(r.creation_cost, 33.0)
	# patrones, estadisticas personalizadas y estadisticas sin regla
	var p := _eval({"stats": {"ELEM_AFF.fire": 0.2, "ELEM_RES.ice": 0.1, "FURIA": 50}})
	assert_almost(_item(p, "stats.ELEM_AFF.fire")["amount"], 60.0)
	assert_eq(_item(p, "stats.ELEM_AFF.fire")["rule"], "stats.patterns.ELEM_AFF.*")
	assert_almost(_item(p, "stats.ELEM_RES.ice")["amount"], 25.0)
	assert_almost(_item(p, "stats.FURIA")["amount"], 10.0, 1e-9, "estadistica personalizada: regla custom")
	assert_eq(_item(p, "stats.FURIA")["rule"], "stats.custom")
	var no_custom := _eval({"stats": {"FURIA": 50}}, {}, _profile(func(d): d["costs"]["stats"].erase("custom")))
	assert_eq(no_custom.unevaluable.size(), 1, "sin regla: no evaluable, sin precio")
	assert_almost(no_custom.creation_cost, 0.0)


func test_rounding_comes_from_the_profile() -> void:
	var ceil_p := _profile(func(d): d["rounding"] = {"mode": "ceil", "decimals": 1})
	var r := _eval({"stats": {"HP": 1001}}, {}, ceil_p)
	assert_almost(_item(r, "stats.HP")["amount"], 0.1, 1e-9, "0,05 redondeado hacia arriba a 1 decimal")
	var none_p := _profile(func(d): d["rounding"] = {"mode": "none", "decimals": 0})
	assert_almost(_item(_eval({"stats": {"HP": 1001}}, {}, none_p), "stats.HP")["amount"], 0.05, 1e-9)


# --- trazabilidad y contrato de la formula ----------------------------------------------------------------------------

func test_breakdown_is_traceable_and_reconciles_with_the_total() -> void:
	var r := _eval({"stats": {"ATK": 160, "HP": 700}, "resources": {"mana": {"initial": 50, "max": 100}},
		"abilities": [_dmg("a1", "ATK_X".replace("ATK_X", "caster.ATK * 1.5"), {"cooldown": 2, "cost": {"mana": 20}}),
			{"id": "p1", "targeting": "self", "passive": {"modifiers": [{"stat": "DEF", "kind": "flat", "value": 20}]}}]})
	assert_eq(r.technical_errors, [])
	var total := 0.0
	for it in r.items:
		if it["counted"]:
			total += float(it["amount"])
			assert_true(it["rule"] != "" and it["origin"] != "", "cada item lleva regla y origen: %s" % it["id"])
			if it["kind"] in ["stat", "stat_credit", "ability", "resource", "passive_modifier"]:
				assert_true(str(it["formula"]) != "" and not (it["facts"] as Dictionary).is_empty(), "formula y hechos de %s" % it["id"])
	assert_almost(total, r.creation_cost, 1e-9, "el desglose suma exactamente el coste de creacion")
	assert_almost(r.gross - r.credits_applied, r.creation_cost, 1e-9)
	assert_almost(r.remaining, r.budget_points - r.creation_cost)
	# jerarquia: la operacion es informativa (no se cuenta dos veces) y cuelga de la habilidad
	var op := _item(r, "ability:a1/effects[0]")
	assert_false(op["counted"])
	assert_eq(op["parent"], "ability:a1")
	# determinista y serializable
	var r2 := _eval({"stats": {"ATK": 160, "HP": 700}, "resources": {"mana": {"initial": 50, "max": 100}},
		"abilities": [_dmg("a1", "caster.ATK * 1.5", {"cooldown": 2, "cost": {"mana": 20}}),
			{"id": "p1", "targeting": "self", "passive": {"modifiers": [{"stat": "DEF", "kind": "flat", "value": 20}]}}]})
	assert_eq(JSON.stringify(r.to_dict()), JSON.stringify(r2.to_dict()))
	var md := r.to_markdown()
	assert_contains(md, "PRUEBA")
	assert_contains(md, "ability:a1")
	assert_contains(md, "Coste de creacion")


func test_reports_are_labelled_as_tests_only_for_illustrative_profiles() -> void:
	assert_true(_eval().labels().size() == 1)
	assert_contains(" ".join(_eval().warnings), "PRUEBA")
	var real := _profile(func(d): d["illustrative"] = false)
	var r := _eval({}, {}, real)
	assert_eq(r.labels(), [])
	assert_eq(r.warnings, [])


# --- habilidades: operaciones y restricciones -------------------------------------------------------------------------

func test_ability_cost_comes_from_operations_and_rules() -> void:
	var r := _eval({"abilities": [_dmg("hit")]})
	# damage: 100 * 0.35 * (1 + 0.2 * true_share) = 42 ; habilidad: 42 + 3
	assert_almost(_item(r, "ability:hit/effects[0]")["amount"], 42.0)
	assert_almost(_item(r, "ability:hit")["amount"], 45.0)
	assert_almost(r.creation_cost, 45.0)
	# la potencia sale de las formulas del propio contenido (estadisticas incluidas)
	var strong := _eval({"stats": {"ATK": 200}, "abilities": [_dmg("hit", "caster.ATK")]})
	var weak := _eval({"abilities": [_dmg("hit", "caster.ATK")]})
	assert_true(_item(strong, "ability:hit")["amount"] > _item(weak, "ability:hit")["amount"])
	# otras operaciones
	var heal := _eval({"abilities": [{"id": "h", "targeting": "self", "effects": [{"type": "heal", "formula": "200"}]}]})
	assert_almost(_item(heal, "ability:h/effects[0]")["amount"], 60.0)
	var res := _eval({"resources": {"mana": {"initial": 50, "max": 100}}, "abilities": [{"id": "m", "targeting": "self", "effects": [
		{"type": "modify_resource", "resource": "mana", "amount": 30}, {"type": "emit_event", "name": "x"}, {"type": "metric", "name": "m", "amount": 1}]}]})
	assert_almost(_item(res, "ability:m/effects[0]")["amount"], 9.0)
	assert_almost(_item(res, "ability:m/effects[1]")["amount"], 0.0)
	assert_eq(_item(res, "ability:m/effects[1]")["rule"], "free.operations")


func test_restrictions_reduce_the_cost_and_flexibility_raises_it() -> void:
	var plain := _cost({"resources": {"mana": {"initial": 100, "max": 100}}, "abilities": [_dmg("x")]})
	var variants := {
		"cooldown": {"cooldown": 3}, "recurso": {"cost": {"mana": 50}}, "usos por combate": {"uses_per_combat": 2},
		"usos por turno": {"uses_per_turn": 1}, "requisito": {"requires": {"self.hp_ratio": {"lt": 0.5}}},
		"canalizada": {"cast_time": 3},
		"reaccion con probabilidad": {"action_type": "reaction", "trigger": {"event": "damage_dealt", "chance": 0.3, "target": "event_source"}},
	}
	for k in variants:
		var c := _cost({"resources": {"mana": {"initial": 100, "max": 100}}, "abilities": [_dmg("x", "100", variants[k])]})
		assert_true(c < plain, "%s abarata (%s < %s)" % [k, str(c), str(plain)])
	var free_action := _cost({"resources": {"mana": {"initial": 100, "max": 100}}, "abilities": [_dmg("x", "100", {"action_type": "free"})]})
	assert_true(free_action > plain, "una accion gratuita vale mas")
	var more_targets := _cost({"resources": {"mana": {"initial": 100, "max": 100}}, "abilities": [_dmg("x", "100", {"target_count": 3})]})
	assert_true(more_targets > plain)
	var cd := _eval({"abilities": [_dmg("x", "100", {"cooldown": 3})]})
	assert_almost(_item(cd, "ability:x")["facts"]["cooldown"], 3.0)
	assert_almost(_item(cd, "ability:x")["amount"], round(42.0 / 1.36 + 3.0))


func test_no_synergy_surcharge_cost_is_the_sum_of_parts() -> void:
	var a := _dmg("a1", "100")
	var b := {"id": "b1", "targeting": "self", "effects": [{"type": "heal", "formula": "150"}]}
	var c := {"id": "c1", "targeting": "self", "passive": {"modifiers": [{"stat": "ATK", "kind": "flat", "value": 50}]}}
	var only := {"a": _cost({"abilities": [a]}), "b": _cost({"abilities": [b]}), "c": _cost({"abilities": [c]})}
	assert_almost(_cost({"abilities": [a, b, c]}), only["a"] + only["b"] + only["c"], 1e-9, "suma simple, sin recargo por sinergias")
	var with_stats := _cost({"stats": {"ATK": 200}, "abilities": [a, b]})
	assert_almost(with_stats, 60.0 + only["a"] + only["b"], 1e-9)


func test_passive_modifiers_and_artifact_are_priced_by_origin() -> void:
	var r := _eval({"abilities": [{"id": "p", "targeting": "self", "passive": {"modifiers": [
		{"stat": "ATK", "kind": "flat", "value": 50}, {"stat": "DEF", "kind": "pct_add", "value": 0.5}, {"stat": "SPD", "kind": "mult", "value": 1.1}]}}],
		"artifact": {"id": "staff", "modifiers": [{"stat": "MAG", "kind": "flat", "value": 30}],
			"abilities": [_dmg("staff_hit", "50")], "resources": {"rune": {"initial": 3, "max": 3}}}})
	assert_eq(r.technical_errors, [])
	assert_almost(_item(r, "ability:p/passive:ATK:flat")["amount"], 30.0)
	assert_almost(_item(r, "ability:p/passive:DEF:pct_add")["amount"], 20.0, 1e-9, "pct_add 50% de 100 = +50 x 0,4")
	assert_almost(_item(r, "ability:p/passive:SPD:mult")["amount"], 8.0, 1e-9)
	var art := _item(r, "artifact.modifiers:MAG:flat")
	assert_eq(art["origin"], "artifact:staff")
	assert_almost(art["amount"], 18.0)
	assert_eq(_item(r, "ability:staff_hit")["origin"], "artifact:staff")
	assert_eq(_item(r, "resource:rune")["origin"], "artifact:staff")
	# modificadores que no se pueden valorar (min/max): no evaluables
	var mm := _eval({"abilities": [{"id": "p", "targeting": "self", "passive": {"modifiers": [{"stat": "ATK", "kind": "max", "value": 50}]}}]})
	assert_eq(mm.unevaluable.size(), 1)


# --- desventajas -------------------------------------------------------------------------------------------------------

func test_disadvantages_grant_automatic_credits_never_author_declared() -> void:
	var neg_passive := _eval({"abilities": [{"id": "curse", "targeting": "self", "passive": {"modifiers": [{"stat": "ATK", "kind": "flat", "value": -40}]}}]})
	assert_true(neg_passive.creation_cost < 0.0 or neg_passive.credits_raw > 0.0)
	assert_eq(_item(neg_passive, "ability:curse/passive:ATK:flat")["kind"], "modifier_credit")
	var recoil := _eval({"abilities": [{"id": "r", "targeting": "enemy", "effects": [
		{"type": "damage", "components": [{"damage_type": "true", "formula": "100"}]},
		{"type": "damage", "on": "caster", "components": [{"damage_type": "true", "formula": "100"}]}]}]})
	var w := _item(recoil, "ability:r/effects[1]")
	assert_eq(w["kind"], "weakness")
	assert_almost(w["amount"], -15.0)
	assert_true(w["credit"])
	# vulnerabilidad elemental = estadistica negativa = credito
	assert_true(_item(_eval({"stats": {"ELEM_RES.fire": -0.2}}), "stats.ELEM_RES.fire")["amount"] < 0.0)
	# el autor no puede declarar costes ni creditos: se rechaza por propiedad desconocida
	for key in ["creation_cost", "cost_pc", "pc", "credits", "weaknesses", "disadvantages", "budget"]:
		var r := _eval({key: 100})
		assert_true(r.technical_errors.size() > 0, "debe rechazar '%s'" % key)
		assert_contains(" ".join(r.technical_errors), "propiedad desconocida")
	var ab := _eval({"abilities": [_dmg("x", "100", {"creation_cost": 1})]})
	assert_true(ab.technical_errors.size() > 0)


func test_credits_are_capped_by_the_profile() -> void:
	var r := _eval({"stats": {"HP": 100, "DEF": 10, "RES": 10, "ATK": 120}})
	# creditos brutos (HP -23, DEF -18, RES -18 = -59) frente a bruto 12; tope 50% => 6
	assert_almost(r.gross, 12.0 + 0.0)
	assert_almost(r.credits_raw, 59.0)
	assert_almost(r.credits_applied, 6.0)
	assert_eq(_count(r, "credit_cap"), 1)
	assert_almost(r.creation_cost, 6.0, 1e-9, "bruto - creditos aplicados")
	var total := 0.0
	for it in r.items:
		if it["counted"]:
			total += it["amount"]
	assert_almost(total, r.creation_cost, 1e-9, "el ajuste del tope mantiene el desglose cuadrado")
	var no_cap := _eval({"stats": {"HP": 100, "DEF": 10, "RES": 10, "ATK": 120}}, {}, _profile(func(d): d.erase("credit_cap")))
	assert_almost(no_cap.creation_cost, 12.0 - 59.0)
	assert_eq(_count(no_cap, "credit_cap"), 0)


# --- IA y ataque basico gratuitos ------------------------------------------------------------------------------------

func test_ai_and_basic_attack_are_free_enhancements_are_not() -> void:
	var base := {"abilities": [_dmg("x")]}
	var plain := _cost(base)
	var with_ai := _cost({"abilities": [_dmg("x")], "ai": {"type": "scored", "weights": {"damage": 1}}})
	var with_tree := _cost({"abilities": [_dmg("x")], "ai": {"type": "behavior_tree", "root": {"type": "action", "ability": "x"}}})
	assert_almost(with_ai, plain)
	assert_almost(with_tree, plain)
	var r := _eval({"abilities": [_dmg("x")], "ai": {"type": "scored"}, "basic_attack": true})
	assert_almost(_item(r, "ai")["amount"], 0.0)
	assert_false(_item(r, "ai")["counted"])
	assert_almost(_item(r, "basic_attack")["amount"], 0.0)
	assert_almost(_cost({"basic_attack": true, "abilities": [_dmg("x")]}), plain, 1e-9, "tener ataque basico no cuesta")
	assert_true(_cost({"basic_attack": true, "stats": {"ATK": 150}}) > 0.0, "potenciarlo (ATK) si se valora")
	# una IA programada no puede dar capacidades mecanicas ocultas: no puede mutar el combate
	var sneaky := EntityFactory.build({"id": "x", "team": "A", "basic_attack": false, "scripts": {"s": "fn decide(view) { deal_damage(\"a\", 99); return {wait: true}; }"},
		"ai": {"type": "script", "script": "s"}}, BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())
	assert_true(sneaky["errors"].size() > 0)
	var script_ai := _eval({"scripts": {"s": "fn decide(view) { return {wait: true}; }"}, "ai": {"type": "script", "script": "s"}})
	assert_eq(script_ai.technical_errors, [])
	assert_almost(script_ai.creation_cost, 0.0, 1e-9, "IA programada: gratis")


# --- estados y referencias no duplicadas -----------------------------------------------------------------------------

func test_status_definitions_are_charged_once_applications_each_time() -> void:
	var stun := {"id": "freeze_x", "duration": 2, "flags": {"skip_turn": true}, "modifiers": [{"stat": "SPD", "kind": "flat", "value": -30}]}
	var a1 := {"id": "a1", "targeting": "enemy", "effects": [{"type": "apply_status", "status": "freeze_x", "duration": 2}]}
	var a2 := {"id": "a2", "targeting": "enemy", "effects": [{"type": "apply_status", "status": "freeze_x", "duration": 3}]}
	var one := _eval({"statuses": [stun], "abilities": [a1]})
	var two := _eval({"statuses": [stun], "abilities": [a1, a2]})
	assert_eq(_count(two, "status:freeze_x"), 1, "la definicion referenciada por dos habilidades se cobra una vez")
	assert_eq(_count(one, "status:freeze_x"), 1)
	var def_amount: float = _item(one, "status:freeze_x")["amount"]
	assert_true(def_amount > 0.0)
	var app1: float = _item(two, "ability:a1")["amount"]
	var app2: float = _item(two, "ability:a2")["amount"]
	assert_almost(two.creation_cost, app1 + app2 + def_amount, 1e-9, "cada aplicacion paga lo suyo; la definicion una vez")
	assert_true(app2 > app1, "mas duracion, mas coste")
	# una definicion sin referenciar no se cobra
	assert_almost(_cost({"statuses": [stun]}), 0.0)
	# estados nativos (datos del motor) tambien se valoran una vez
	var poison := _eval({"abilities": [{"id": "p", "targeting": "enemy", "effects": [{"type": "apply_status", "status": "poison", "stacks": 2, "duration": 3}]}]})
	assert_eq(_count(poison, "status:poison"), 1)
	assert_eq(_item(poison, "status:poison")["origin"], "native")
	assert_eq(poison.unevaluable.size(), 0, str(poison.unevaluable))


func test_status_effects_and_forms_are_priced_through_the_same_rules() -> void:
	var burn := {"id": "scorch", "duration": 3, "periodic": [{"on": "turn_start", "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "caster.MAG * 0.2"}]}]}]}
	var r := _eval({"statuses": [burn], "abilities": [{"id": "ig", "targeting": "enemy", "effects": [{"type": "apply_status", "status": "scorch"}]}]})
	assert_eq(r.technical_errors, [], str(r.technical_errors))
	var d := _item(r, "status:scorch")
	assert_true(d["facts"]["inner"] > 0.0, "el dano periodico se valora")
	assert_eq(r.unevaluable.size(), 0)
	var form := {"id": "beast", "duration": 5, "form": {"add_abilities": [_dmg("claw", "60")]}}
	var f := _eval({"statuses": [form], "abilities": [{"id": "shift", "targeting": "self", "effects": [{"type": "apply_status", "status": "beast"}]}]})
	assert_eq(f.technical_errors, [], str(f.technical_errors))
	assert_true(_item(f, "status:beast")["amount"] >= 40.0, "una transformacion cuesta")


func test_summons_are_valued_as_characters_per_instance() -> void:
	var tmpl := {"stats": {"HP": 300, "ATK": 140}, "abilities": [_dmg("bite", "80")], "basic_attack": false}
	var s1 := {"id": "call1", "targeting": "self", "effects": [{"type": "summon", "template": "wolf", "count": 1}]}
	var s2 := {"id": "call2", "targeting": "self", "effects": [{"type": "summon", "template": "wolf", "count": 2}]}
	var r := _eval({"summons": {"wolf": tmpl}, "abilities": [s1, s2]})
	assert_eq(r.technical_errors, [], str(r.technical_errors))
	var tc := _item(r, "summon_template:wolf")
	assert_false(tc["counted"], "la plantilla es informativa")
	assert_true(tc["amount"] > 0.0)
	var o1: float = _item(r, "ability:call1/effects[0]")["amount"]
	var o2: float = _item(r, "ability:call2/effects[0]")["amount"]
	assert_almost(o1, round(tc["amount"] * 0.8), 1.0)
	assert_almost(o2, o1 * 2.0, 1.0, "cada instancia concedida se valora con el alcance de la capacidad")
	var bad := _eval({"summons": {"wolf": {"abilities": [{"id": "s", "targeting": "self", "effects": [{"type": "script", "script": "x"}]}]}},
		"abilities": [s1]})
	assert_true(bad.technical_errors.size() > 0 or bad.unevaluable.size() > 0)


# --- no evaluables y contratos de script ------------------------------------------------------------------------------

func test_unpriceable_components_are_flagged_without_inventing_a_price() -> void:
	var no_copy := _profile(func(d): d["costs"]["operations"].erase("copy_action"))
	var r := _eval({"abilities": [{"id": "mimic", "targeting": "enemy", "effects": [{"type": "copy_action"}]}]}, {}, no_copy)
	assert_eq(r.unevaluable.size(), 1)
	assert_contains(r.unevaluable[0]["reason"], "no tiene regla de coste")
	var it := _item(r, "ability:mimic/effects[0]")
	assert_true(it["unevaluable"])
	assert_almost(it["amount"], 0.0, 1e-9, "sin precio")
	assert_false(it["counted"])
	assert_false(r.evaluable())
	# formulas que no se pueden resolver sin contexto
	var nf := _eval({"abilities": [_dmg("x", "foo.bar * 2")]})
	assert_true(nf.technical_errors.size() > 0, "formulas con origenes no permitidos no se valoran")


func test_scripts_priced_only_with_verifiable_contract() -> void:
	var src := "fn run(ctx) { for t in ctx.targets { deal_damage(t, 50, {\"damage_type\": \"true\"}); } }"
	var power_free := "fn run(ctx) { emit(\"ping\"); set_var(\"n\", 1); }"
	var abil := func(c: Variant) -> Dictionary:
		var e := {"type": "script", "script": "s"}
		if c != null:
			e["contract"] = c
		return {"id": "z", "targeting": "enemy", "effects": [e]}
	# sin contrato y con poder mecanico: no evaluable
	var r1 := _eval({"scripts": {"s": src}, "abilities": [abil.call(null)]})
	assert_eq(r1.technical_errors, [])
	assert_eq(r1.unevaluable.size(), 1)
	assert_contains(r1.unevaluable[0]["reason"], "sin `contract`")
	# sin poder mecanico: valorable (gratis)
	var r2 := _eval({"scripts": {"s": power_free}, "abilities": [abil.call(null)]})
	assert_eq(r2.unevaluable.size(), 0)
	assert_eq(_item(r2, "ability:z/effects[0]")["rule"], "script.sin_poder_mecanico")
	# con contrato: se valora como dano de peor caso (siempre impacta, critico, penetracion total)
	var r3 := _eval({"scripts": {"s": src}, "abilities": [abil.call({"max_damage": 100})]})
	assert_eq(r3.unevaluable.size(), 0, str(r3.unevaluable))
	var sc := _item(r3, "ability:z/effects[0]/deal_damage")
	assert_eq(sc["kind"], "script_contract")
	assert_almost(sc["facts"]["pen_pct"], 1.0)
	assert_almost(sc["facts"]["always_hit"], 1.0)
	var declared := _eval({"abilities": [_dmg("z", "100", {"effects": [{"type": "damage", "always_hit": true, "can_crit": true, "components": [{"damage_type": "physical", "formula": "100", "pen_pct": 1.0}]}]})]})
	assert_almost(_item(r3, "ability:z/effects[0]/deal_damage")["amount"], _item(declared, "ability:z/effects[0]")["amount"], 1.0, "el contrato cuesta como el dano declarativo equivalente de peor caso")
	assert_true(_item(r3, "ability:z")["amount"] > 0.0)
	# un tope mayor cuesta mas
	var r4 := _eval({"scripts": {"s": src}, "abilities": [abil.call({"max_damage": 300})]})
	assert_true(_item(r4, "ability:z")["amount"] > _item(r3, "ability:z")["amount"])
	# contrato incompleto o que no puede cubrir lo que usa: error tecnico al construir
	var heal_src := "fn run(ctx) { heal(ctx.caster, 10); }"
	var inc := _eval({"scripts": {"s": heal_src}, "abilities": [abil.call({"max_damage": 100})]})
	assert_contains(" ".join(inc.technical_errors), "max_heal")
	var unc := _eval({"scripts": {"s": "fn run(ctx) { apply_status(ctx.caster, \"poison\"); }"}, "abilities": [abil.call({"max_damage": 100})]})
	assert_contains(" ".join(unc.technical_errors), "no puede cubrir")
	# sin cobertura posible (modify_resource sin contrato): no evaluable
	var mr := _eval({"scripts": {"s": "fn run(ctx) { modify_resource(ctx.caster, \"mana\", 5); }"}, "abilities": [abil.call(null)]})
	assert_eq(mr.unevaluable.size(), 1)
	# contratos mal formados
	assert_true(OperationRegistry.new().validate_effect({"type": "script", "script": "s", "contract": {"max_damage": -1}}).size() > 0)
	assert_true(OperationRegistry.new().validate_effect({"type": "script", "script": "s", "contract": {"oro": 5}}).size() > 0)
	assert_true(OperationRegistry.new().validate_effect({"type": "script", "script": "s", "contract": {}}).size() > 0)


func test_script_contract_is_enforced_by_the_engine_at_runtime() -> void:
	var src := "fn run(ctx) { deal_damage(ctx.targets[0], ctx.args.n, {\"damage_type\": \"true\"}); heal(ctx.caster, ctx.args.h); }"
	var run := func(n: float, h: float, contract: Dictionary) -> CombatEngine:
		var a := ent("a", "A", {"stats": {"SPD": 100, "HP": 500}, "scripts": {"s": src},
			"abilities": [{"id": "zap", "targeting": "enemy", "effects": [{"type": "script", "script": "s", "args": {"n": n, "h": h}, "contract": contract}]}]})
		var t := ent("t", "B", {"stats": {"SPD": 1, "HP": 9000}})
		var eng := engine([a, t])
		ActionResolver.resolve(eng, TurnState.new(a, 1), a, a.get_ability("zap"), [t] as Array[CombatEntity], 0)
		return eng
	var ok: CombatEngine = run.call(100.0, 20.0, {"max_damage": 100, "max_heal": 20})
	assert_false(ok.is_aborted(), "dentro del tope")
	assert_almost(ok.get_entity("t").hp, 8900.0)
	var over: CombatEngine = run.call(101.0, 20.0, {"max_damage": 100, "max_heal": 20})
	assert_true(over.is_aborted())
	assert_eq(over.get_error()["code"], "script_error")
	assert_contains(over.get_error()["message"], "[contrato]")
	assert_almost(over.get_entity("t").hp, 9000.0, 1e-9, "el dano que supera el tope no llega a aplicarse")
	var over_h: CombatEngine = run.call(10.0, 21.0, {"max_damage": 100, "max_heal": 20})
	assert_true(over_h.is_aborted())
	assert_contains(over_h.get_error()["message"], "max_heal")
	# sin contrato no hay tope (se valora como no evaluable, pero se ejecuta)
	var a2 := ent("a", "A", {"stats": {"SPD": 100}, "scripts": {"s": src},
		"abilities": [{"id": "zap", "targeting": "enemy", "effects": [{"type": "script", "script": "s", "args": {"n": 5000, "h": 0}}]}]})
	var t2 := ent("t", "B", {"stats": {"SPD": 1, "HP": 9000}})
	var e2 := engine([a2, t2])
	ActionResolver.resolve(e2, TurnState.new(a2, 1), a2, a2.get_ability("zap"), [t2] as Array[CombatEntity], 0)
	assert_false(e2.is_aborted())


# --- modos -----------------------------------------------------------------------------------------------------------------

func test_free_mode_warns_regulated_mode_rejects() -> void:
	var huge := {"stats": {"ATK": 3000, "MAG": 3000}}
	var free := _eval(huge, {"mode": "free", "budget": "small"})
	assert_true(free.valid(), "libre: se puede exceder el presupuesto")
	assert_false(free.within_budget())
	assert_contains(" ".join(free.warnings), "presupuesto")
	var reg := _eval(huge, {"mode": "regulated", "budget": "small"})
	assert_false(reg.valid())
	assert_contains(" ".join(reg.errors), "[presupuesto]")
	var fits := _eval({"stats": {"ATK": 150}}, {"mode": "regulated", "budget": "small"})
	assert_true(fits.valid())
	assert_true(fits.within_budget())
	assert_almost(fits.remaining, float(_profile().budgets["small"]["points"]) - 30.0, 1e-9)
	# categorias de presupuesto distintas
	for b in ["small", "standard", "large", "epic"]:
		assert_almost(_eval({}, {"budget": b}).budget_points, float(_profile().budgets[b]["points"]))
	# presupuesto global libre: no hay limites por categoria (solo el total)
	var mixed := _eval({"stats": {"ATK": 400}, "abilities": [_dmg("x", "caster.ATK")]}, {"mode": "regulated", "budget": "epic"})
	assert_true(mixed.valid())


func test_regulated_mode_requires_evaluability_free_mode_only_warns() -> void:
	var ents := {"abilities": [{"id": "z", "targeting": "enemy", "effects": [{"type": "script", "script": "s"}]}],
		"scripts": {"s": "fn run(ctx) { deal_damage(ctx.targets[0], 5, {\"damage_type\": \"true\"}); }"}}
	var free := _eval(ents, {"mode": "free"})
	assert_true(free.valid(), "libre: se ejecuta si es tecnicamente valido")
	assert_contains(" ".join(free.warnings), "no_evaluable")
	var reg := _eval(ents, {"mode": "regulated"})
	assert_false(reg.valid(), "reglamentado: fuera hasta que el perfil pueda evaluarlo")
	assert_contains(" ".join(reg.errors), "[no_evaluable]")
	# perfil sin costes
	var tech := BalanceProfile.from_file("res://content/balance/technical_profile.json")
	var nf := _eval({}, {"mode": "free"}, tech)
	assert_true(nf.valid())
	assert_false(nf.evaluable())
	assert_false(_eval({}, {"mode": "regulated"}, tech).valid())


func test_technical_validity_is_required_in_both_modes_and_options_are_validated() -> void:
	for mode in ["free", "regulated"]:
		var r := _eval({"abilities": [{"id": "x", "targeting": "enemy", "effects": [{"type": "apply_status", "status": "no_existe"}]}]}, {"mode": mode})
		assert_false(r.valid(), mode)
		assert_true(r.technical_errors.size() > 0)
		assert_eq(r.items, [], "contenido invalido: no se valora")
	assert_contains(" ".join(_eval({}, {"mode": "magico"}).technical_errors), "modo desconocido")
	assert_contains(" ".join(_eval({}, {"budget": "inexistente"}).technical_errors), "presupuesto desconocido")
	var no_budget := _profile(func(d): d.erase("default_budget"))
	var r2 := _eval({}, {"mode": "regulated"}, no_budget)
	assert_contains(" ".join(r2.errors), "requiere un presupuesto")
	assert_true(_eval({}, {"mode": "free"}, no_budget).valid())


func test_equal_cost_does_not_claim_equal_power_and_reports_say_so() -> void:
	# la valoracion es determinista y la misma para el mismo contenido; no es una afirmacion de poder
	var a := _eval({"stats": {"ATK": 200}})
	var b := _eval({"stats": {"MAG": 200}})
	assert_almost(a.creation_cost, b.creation_cost)
	assert_true(BalanceReport.new().to_markdown().length() > 0)
	assert_contains(a.to_markdown(), "no implica igualdad de poder")
	assert_contains(a.to_dict()["note"], "evaluacion empirica")


# --- integracion --------------------------------------------------------------------------------------------------------------

func _hero_pkg(stats: Dictionary, name: String = "t/hero") -> String:
	var d := "%s/p%d" % [TMP, Time.get_ticks_usec()]
	var files := {
		"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": name, "version": "1.0.0", "type": "character", "name": "H"}),
		"character.json": JSON.stringify({"schema": "simhalla.character/1", "name": "Hero", "stats": stats, "basic_attack": true})}
	for rel in files:
		var p: String = d.path_join(rel)
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string(files[rel])
		f.close()
	return d


func test_importer_applies_balance_modes() -> void:
	var lib := ContentLibrary.new("%s/lib%d" % [TMP, Time.get_ticks_usec()])
	var prof := BalanceProfile.from_file(REF)
	var imp := PackageImporter.new(lib)
	imp.balance = {"profile": prof, "mode": "regulated", "budget": "small"}
	var big := imp.validate(_hero_pkg({"ATK": 2000}))
	assert_false(big.ok())
	assert_contains("\n".join(big.errors), "equilibrio: [presupuesto]")
	assert_true(big.balance.has("creation_cost"))
	var small := imp.validate(_hero_pkg({"ATK": 150}))
	assert_true(small.ok(), "\n".join(small.errors))
	assert_almost(small.balance["creation_cost"], 30.0)
	assert_contains(" ".join(small.warnings), "PRUEBA")
	# modo libre: importa con aviso
	var imp_free := PackageImporter.new(lib)
	imp_free.balance = {"profile": prof, "mode": "free", "budget": "small"}
	var rep := imp_free.import_package(_hero_pkg({"ATK": 2000}, "t/big"))
	assert_true(rep.ok(), "\n".join(rep.errors))
	assert_true(rep.stored)
	assert_contains(" ".join(rep.warnings), "equilibrio")
	# sin configuracion de equilibrio, el importador solo valida lo tecnico (compatibilidad)
	assert_true(PackageImporter.new(lib).validate(_hero_pkg({"ATK": 2000})).ok())
	ContentLibrary._remove_tree(TMP)


func test_rune_caster_example_chain_priced_via_contract_overload_not_evaluable() -> void:
	var imp := PackageImporter.new(ContentLibrary.new("%s/lib%d" % [TMP, Time.get_ticks_usec()]))
	imp.balance = {"profile": BalanceProfile.from_file(REF), "mode": "regulated", "budget": "standard"}
	var rep := imp.validate("res://content/packages/rune_caster")
	assert_false(rep.ok(), "overload no es evaluable: fuera en modo reglamentado")
	var text := "\n".join(rep.errors)
	assert_contains(text, "ability:overload")
	assert_false(text.contains("ability:chain_bolt/effects[0]: script"), "el rayo en cadena SI se valora (contrato)")
	var names: Array = rep.balance["items"].map(func(i): return i["id"])
	assert_contains(names, "ability:chain_bolt/effects[0]/deal_damage")
	imp.balance["mode"] = "free"
	var free := imp.validate("res://content/packages/rune_caster")
	assert_true(free.ok(), "\n".join(free.errors))
	assert_eq(free.balance["unevaluable"].size(), 1)
	ContentLibrary._remove_tree(TMP)


func test_duel_runner_blocks_regulated_violations_and_reports_free_ones() -> void:
	var cfg := {"seed": 1, "entities": [
		{"path": "res://content/fixtures/entities/attacker_a.json", "overrides": {"team": "A"}},
		{"path": "res://content/fixtures/entities/attacker_b.json", "overrides": {"team": "B"}}],
		"balance": {"profile": REF, "mode": "regulated", "budget": "standard"}}
	var out := DuelRunner.run(cfg)
	assert_true(out["ok"], str(out["errors"]))
	assert_eq(out["balance"].size(), 2)
	assert_true(out["balance"][0]["valid"])
	cfg["balance"]["budget"] = "small"
	cfg["entities"][0]["overrides"]["stats"] = {"ATK": 4000}
	var blocked := DuelRunner.run(cfg)
	assert_false(blocked["ok"])
	assert_contains(" ".join(blocked["errors"]), "equilibrio [presupuesto]")
	cfg["balance"]["mode"] = "free"
	var allowed := DuelRunner.run(cfg)
	assert_true(allowed["ok"], str(allowed["errors"]))
	assert_false(allowed["balance"][0]["within_budget"])
	assert_false(allowed["result"].is_aborted())
	# sin "balance" el comportamiento no cambia
	var plain := DuelRunner.run({"seed": 1, "entities": cfg["entities"].map(func(e): return {"path": e["path"], "overrides": {"team": e["overrides"]["team"]}})})
	assert_true(plain["ok"])
	assert_eq(plain["balance"], [])


func test_all_fixtures_are_valued_without_technical_errors() -> void:
	var dir := DirAccess.open("res://content/fixtures/entities")
	var n := 0
	for f in dir.get_files():
		if f.ends_with(".json"):
			var d: Dictionary = EntityFactory.load_json("res://content/fixtures/entities/" + f)
			var r := BalanceEvaluator.evaluate(d, _profile(), Ruleset.from_dict({}), OperationRegistry.new(), {"mode": "free"})
			assert_eq(r.technical_errors, [], f)
			assert_true(r.valid(), f)
			n += 1
	assert_true(n >= 6)
