extends Phase3Case
## Fase 4: IA — estrategias puntuadas, condiciones con memoria/prediccion, maquina de estados,
## politica de reacciones, privacidad de la vista y perfiles intercambiables.

const PKG := "res://content/packages/ai_profiles/"


class _Spy extends AIController:
	var inner: AIController
	var views: Array = []
	var predict_every_turn: bool = false

	func _init(i: AIController) -> void:
		inner = i

	func decide(view: Dictionary) -> AIDecision:
		views.append(view.duplicate(true))
		if predict_every_turn:
			for la in view["legal_actions"]:
				for t in la["targets"]:
					AIPredictor.evaluate(view, la["ability_id"], t)
		return inner.decide(view)

	func wants_memory() -> bool:
		return inner.wants_memory()


func _view(eng: CombatEngine, id: String) -> Dictionary:
	var e := eng.get_entity(id)
	return ViewBuilder.build(eng, e, TurnState.new(e, 1))


func _decide(eng: CombatEngine, id: String) -> AIDecision:
	var e := eng.get_entity(id)
	var d := e.ai.decide(_view(eng, id))
	AIMemory.apply_ops(e, d.memory_ops)
	return d


func _cast(eng: CombatEngine, caster: CombatEntity, ability: String, target: CombatEntity) -> void:
	ActionResolver.resolve(eng, TurnState.new(caster, 1), caster, caster.get_ability(ability), [target] as Array[CombatEntity], 0)


func _dummy(id: String = "t", team: String = "B", extra: Dictionary = {}) -> CombatEntity:
	var d := {"stats": {"SPD": 1, "HP": 9000, "EVA": 0.0}}
	d.merge(extra, true)
	return ent(id, team, d)


func _phys(id: String, amount: String) -> Dictionary:
	return dmg_ability(id, amount, {"effects": [{"type": "damage", "always_hit": true, "can_crit": false,
		"components": [{"damage_type": "physical", "formula": amount}]}]})


func _mana() -> Dictionary:
	return {"mana": {"initial": 100, "min": 0, "max": 100}}


# --- puntuaciones ----------------------------------------------------------------------------------

func _scored_duelist(cfg: Dictionary, enemy_hp: int = 150) -> CombatEngine:
	var a := ent("a", "A", {"stats": {"SPD": 100, "HP": 500}, "resources": _mana(), "ai": cfg,
		"abilities": [dmg_ability("chip", "100"), dmg_ability("kill", "160", {"cost": {"mana": 50}})]})
	return engine([a, _dummy("b", "B", {"stats": {"SPD": 1, "HP": enemy_hp}})])


func test_scored_weights_change_the_choice_deterministically() -> void:
	var lethal := _scored_duelist({"type": "scored", "weights": {"lethal": 5, "cost": -1}})
	var d := _decide(lethal, "a")
	assert_eq(d.ability_id, "kill", "el potencial letal compensa el coste")
	assert_eq(d.reason, "scored")
	assert_eq(d.target_ids, ["b"])
	assert_true(d.details["top"].size() == 2, "traza de candidatos")
	assert_true(d.details["top"][0]["score"] > d.details["top"][1]["score"])
	var thrifty := _scored_duelist({"type": "scored", "weights": {"damage": 1, "cost": -3}})
	assert_eq(_decide(thrifty, "a").ability_id, "chip", "con coste alto se ahorra")
	# mismo estado, misma decision (sin azar estrategico)
	var again := _scored_duelist({"type": "scored", "weights": {"damage": 1, "cost": -3}})
	assert_eq(_decide(again, "a").to_dict(), _decide(thrifty, "a").to_dict())


func test_scored_ties_resolve_by_view_order_and_bias_modifiers_apply() -> void:
	var eng := _scored_duelist({"type": "scored", "weights": {}})
	assert_eq(_decide(eng, "a").ability_id, "chip", "empate: primera habilidad en el orden de la vista")
	var biased := _scored_duelist({"type": "scored", "bias": {"kill": 0.5}})
	assert_eq(_decide(biased, "a").ability_id, "kill")
	var mod := _scored_duelist({"type": "scored", "bias": {"chip": 1.0}, "modifiers": [{"when": {"self.res.mana": {"ge": 100}}, "bias": {"kill": 5}}]})
	var d := _decide(mod, "a")
	assert_eq(d.ability_id, "kill", "el modificador se activa por la condicion")
	assert_eq(d.details["modifiers"], [0])
	var excl := _scored_duelist({"type": "scored", "bias": {"kill": 9}, "exclude": ["kill"]})
	assert_eq(_decide(excl, "a").ability_id, "chip")


func test_scored_wait_below_reserves_the_action() -> void:
	var eng := _scored_duelist({"type": "scored", "weights": {"damage": 1}, "wait_below": 2.0})
	var d := _decide(eng, "a")
	assert_eq(d.kind, AIDecision.Kind.WAIT)
	assert_eq(d.reason, "reserve")


func test_scored_heals_when_hurt_and_never_heals_enemies_or_hurts_allies() -> void:
	var a := ent("a", "A", {"stats": {"SPD": 100, "HP": 400}, "resources": _mana(),
		"ai": {"type": "scored", "weights": {"damage": 1, "heal": 1, "need": 3}},
		"abilities": [dmg_ability("chip", "50"), {"id": "mend", "targeting": "any", "effects": [{"type": "heal", "formula": "300"}]}]})
	var ally := _dummy("al", "A", {"stats": {"SPD": 1, "HP": 400}})
	var foe := _dummy("f", "B", {"stats": {"SPD": 1, "HP": 400}})
	var eng := engine([a, ally, foe])
	hit(eng, foe, a, 300.0)
	var d := _decide(eng, "a")
	assert_eq(d.ability_id, "mend")
	assert_eq(d.target_ids, ["a"], "cura al necesitado, no al rival ni al aliado sano")
	var healthy := engine([ent("a", "A", {"stats": {"SPD": 100, "HP": 400}, "ai": {"type": "scored", "weights": {"damage": 1, "heal": 1, "need": 3}},
		"abilities": [dmg_ability("chip", "50"), {"id": "mend", "targeting": "any", "effects": [{"type": "heal", "formula": "300"}]}]}),
		_dummy("al", "A", {"stats": {"SPD": 1, "HP": 400}}), _dummy("f", "B", {"stats": {"SPD": 1, "HP": 400}})])
	var d2 := _decide(healthy, "a")
	assert_eq(d2.ability_id, "chip")
	assert_eq(d2.target_ids, ["f"], "dano a rivales, nunca a aliados")


# --- prediccion ------------------------------------------------------------------------------------

func test_prediction_is_estimate_until_observed_and_never_reads_hidden_stats() -> void:
	var mk := func(enemy_def: int) -> CombatEngine:
		var a := ent("a", "A", {"stats": {"SPD": 100, "HP": 500, "ACC": 1.0}, "ai": {"type": "scored", "weights": {"damage": 1}}, "abilities": [_phys("hit", "100")]})
		return engine([a, _dummy("b", "B", {"stats": {"SPD": 1, "HP": 150, "DEF": enemy_def}})])
	var weak: CombatEngine = mk.call(0)
	var tough: CombatEngine = mk.call(500)
	var p_weak := AIPredictor.damage(_view(weak, "a"), "hit", "b")
	var p_tough := AIPredictor.damage(_view(tough, "a"), "hit", "b")
	assert_eq(p_weak, p_tough, "sin observaciones la estimacion no depende de la DEF oculta")
	assert_false(p_weak["known"])
	assert_almost(p_weak["max"], 100.0)
	assert_almost(p_weak["min"], 0.0)
	assert_false(p_weak["lethal"], "estimacion no conocida: no se afirma letalidad")
	# tras observar un golpe: DEF 100 => 100*100/(100+100) = 50, razon 0.5
	var eng: CombatEngine = mk.call(100)
	_cast(eng, eng.get_entity("a"), "hit", eng.get_entity("b"))
	var v := _view(eng, "a")
	var obs := AIPredictor.observed_ratio(v, "b", "physical", "")
	assert_true(obs["known"])
	assert_almost(obs["ratio"], 0.5)
	var p := AIPredictor.damage(v, "hit", "b")
	assert_true(p["known"])
	assert_almost(p["expected"], 50.0)
	assert_eq(AIPredictor.damage(v, "hit", "b")["lethal"], false, "50 < 100 de vida restante")
	assert_eq(AIPredictor.heal(v, "hit", "a")["known"], false)


func test_prediction_lethal_flags() -> void:
	var a := ent("a", "A", {"stats": {"SPD": 100}, "ai": {"type": "scored"}, "abilities": [dmg_ability("kill", "160"), dmg_ability("chip", "100")]})
	var eng := engine([a, _dummy("b", "B", {"stats": {"SPD": 1, "HP": 150}})])
	var v := _view(eng, "a")
	assert_true(AIPredictor.damage(v, "kill", "b")["lethal"], "dano verdadero: conocido y suficiente")
	assert_false(AIPredictor.damage(v, "chip", "b")["lethal"])
	assert_true(AIPredictor.damage(v, "kill", "b")["lethal_potential"])
	assert_false(AIPredictor.damage(v, "chip", "b")["lethal_potential"])
	assert_almost(AIPredictor.damage(v, "kill", "b")["hit_chance"], 1.0)


func test_predictions_do_not_touch_state_or_rng() -> void:
	var build := func(spy_predicts: bool) -> CombatEngine:
		var a := ent("a", "A", {"stats": {"SPD": 100, "HP": 500}, "resources": _mana(),
			"ai": {"type": "scored", "weights": {"damage": 1, "cost": -0.2}}, "abilities": [dmg_ability("chip", "40", {"effects": [
				{"type": "damage", "components": [{"damage_type": "physical", "formula": "40"}]}]}), dmg_ability("kill", "70", {"cost": {"mana": 10}})]})
		var s := _Spy.new(a.ai)
		s.predict_every_turn = spy_predicts
		a.ai = s
		return engine([a, _dummy("b", "B", {"stats": {"SPD": 60, "HP": 400}})], 9, {"victory": {"limits": {"max_turns": 10, "stagnation_turns": 99}}})
	var plain: CombatEngine = build.call(false)
	var probing: CombatEngine = build.call(true)
	assert_eq(plain.run().log_hash, probing.run().log_hash, "consultar predicciones no altera el combate")


# --- memoria ---------------------------------------------------------------------------------------

func test_memory_records_only_observable_facts_and_resets_per_battle() -> void:
	var a := ent("a", "A", {"stats": {"SPD": 100}, "ai": {"type": "scored", "weights": {"damage": 1}}, "abilities": [dmg_ability("chip", "10")]})
	var b := _dummy("b", "B", {"stats": {"SPD": 1, "HP": 500, "DEF": 300}})
	a.ai_memory["stale"] = 1 # basura de una batalla anterior
	var eng := engine([a, b])
	assert_false(a.ai_memory.has("stale"), "la memoria no se hereda entre batallas")
	_cast(eng, a, "chip", b)
	hit(eng, b, a, 7.0)
	var o: Dictionary = a.ai_memory["obs"]["b"]
	assert_eq(o["dealt_n"], 1)
	assert_almost(o["dealt_total"], 10.0)
	assert_eq(o["taken_n"], 1)
	assert_almost(o["taken_total"], 7.0)
	assert_eq(a.ai_memory["last_hit_by"], "b")
	assert_eq(a.ai_memory["history"].size(), 0, "el historial solo registra decisiones (action_selected)")
	assert_false(b.ai_memory["obs"].has("a"), "el pasivo no acumula observaciones")
	# la vista copia: mutar no afecta a la memoria real
	var v := _view(eng, "a")
	v["self"]["memory"]["obs"].clear()
	assert_true(a.ai_memory["obs"].has("b"))
	# la memoria de uno no es la del otro
	assert_false(a.ai_memory == b.ai_memory)


func test_memory_history_is_bounded_and_ops_validated() -> void:
	var e := ent("a", "A", {"ai": {"type": "passive"}})
	e.ai_memory = AIMemory.fresh()
	var ops: Array = [{"op": "set", "key": "x", "value": 3}, {"op": "incr", "key": "x", "value": 2}, {"op": "set", "key": "", "value": 1},
		{"op": "set", "key": "bad", "value": [1]}, {"op": "incr", "key": "t", "value": "no"}, {"op": "boom"}, {"op": "set", "key": "flag", "value": true}]
	assert_eq(AIMemory.apply_ops(e, ops).size(), 3)
	assert_almost(float(e.ai_memory["vars"]["x"]), 5.0)
	assert_eq(e.ai_memory["vars"]["flag"], true)
	for i in AIMemory.VARS_MAX + 10:
		AIMemory.apply_ops(e, [{"op": "set", "key": "v%d" % i, "value": i}])
	assert_true(e.ai_memory["vars"].size() <= AIMemory.VARS_MAX, "limite de variables")
	# historial acotado en un combate real
	var a := ent("a", "A", {"stats": {"SPD": 100}, "ai": {"type": "scored", "weights": {"damage": 1}}, "abilities": [dmg_ability("chip", "1")]})
	var eng := engine([a, _dummy("b", "B", {"stats": {"SPD": 1, "HP": 99999}})], 1, {"victory": {"limits": {"max_turns": 40, "stagnation_turns": 99}}})
	eng.run()
	assert_eq(a.ai_memory["history"].size(), AIMemory.HISTORY_MAX)


func test_priority_list_uses_memory_prediction_and_last_attacker() -> void:
	# apertura una sola vez (memoria) y luego remate si es letal (prediccion)
	var cfg := {"type": "priority_list", "rules": [
		{"ability": "kill", "when": {"predict.lethal": {"eq": 1}}},
		{"ability": "opener", "when": {"mem.opened": {"eq": 0}}, "remember": {"set": {"opened": 1}}},
		{"ability": "chip"}]}
	var a := ent("a", "A", {"stats": {"SPD": 100}, "ai": cfg, "abilities": [dmg_ability("chip", "10"), dmg_ability("opener", "20"), dmg_ability("kill", "300")]})
	var eng := engine([a, _dummy("b", "B", {"stats": {"SPD": 1, "HP": 500}})])
	assert_eq(_decide(eng, "a").ability_id, "opener")
	assert_eq(_decide(eng, "a").ability_id, "chip", "la memoria recuerda la apertura")
	var eng2 := engine([ent("a", "A", {"stats": {"SPD": 100}, "ai": cfg, "abilities": [dmg_ability("chip", "10"), dmg_ability("opener", "20"), dmg_ability("kill", "300")]}),
		_dummy("b", "B", {"stats": {"SPD": 1, "HP": 500}})])
	hit(eng2, eng2.get_entity("a"), eng2.get_entity("b"), 495.0)
	assert_eq(_decide(eng2, "a").ability_id, "kill", "remate letal tiene prioridad")
	# last_attacker
	var t := {"type": "priority_list", "rules": [{"ability": "chip", "target": "last_attacker"}]}
	var eng3 := engine([ent("a", "A", {"stats": {"SPD": 100}, "ai": t, "abilities": [dmg_ability("chip", "10")]}), _dummy("b", "B"), _dummy("c", "B")])
	assert_eq(_decide(eng3, "a").kind, AIDecision.Kind.WAIT, "sin agresor conocido, la regla no aplica")
	hit(eng3, eng3.get_entity("c"), eng3.get_entity("a"), 5.0)
	assert_eq(_decide(eng3, "a").target_ids, ["c"])


# --- maquina de estados ----------------------------------------------------------------------------

func _machine() -> Dictionary:
	return {"type": "state_machine", "initial": "attack", "states": {
		"attack": {"strategy": {"type": "priority_list", "rules": [{"ability": "chip", "target": "first_enemy"}]},
			"transitions": [{"to": "recover", "when": {"self.hp_ratio": {"lt": 0.5}}, "remember": {"incr": {"retreats": 1}}}]},
		"recover": {"strategy": {"type": "priority_list", "rules": [{"ability": "mend", "target": "self"}]},
			"transitions": [{"to": "attack", "when": {"self.hp_ratio": {"ge": 0.8}}}]}}}


func _machine_fighter(cfg: Dictionary) -> CombatEntity:
	return ent("a", "A", {"stats": {"SPD": 100, "HP": 400}, "ai": cfg, "abilities": [dmg_ability("chip", "10"),
		{"id": "mend", "targeting": "self", "effects": [{"type": "heal", "formula": "100"}]}]})


func test_state_machine_transitions_and_persists_state() -> void:
	var eng := engine([_machine_fighter(_machine()), _dummy()])
	var a := eng.get_entity("a")
	var d := _decide(eng, "a")
	assert_eq(d.ability_id, "chip")
	assert_eq(d.details["state"], "attack")
	assert_eq(a.ai_memory["state"], "attack", "el estado inicial se fija en la memoria")
	hit(eng, eng.get_entity("t"), a, 250.0) # 150/400 = 0.375 < 0.5
	var d2 := _decide(eng, "a")
	assert_eq(d2.ability_id, "mend")
	assert_eq(d2.details["transition"], {"from": "attack", "to": "recover", "rule": 0})
	assert_eq(a.ai_memory["state"], "recover")
	assert_almost(float(a.ai_memory["vars"]["retreats"]), 1.0)
	var d3 := _decide(eng, "a")
	assert_eq(d3.ability_id, "mend", "se mantiene en recover mientras no se cumpla la salida")
	assert_false(d3.details.has("transition"))
	a.hp = 360.0
	var d4 := _decide(eng, "a")
	assert_eq(d4.ability_id, "chip")
	assert_eq(d4.details["transition"]["to"], "attack")


func test_state_machine_state_turns_in_real_combat() -> void:
	var cfg := {"type": "state_machine", "initial": "s1", "states": {
		"s1": {"strategy": {"type": "priority_list", "rules": [{"ability": "poke"}]}, "transitions": [{"to": "s2", "when": {"state_turns": {"ge": 2}}}]},
		"s2": {"strategy": {"type": "priority_list", "rules": [{"ability": "heavy"}]}}}}
	var a := ent("a", "A", {"stats": {"SPD": 100}, "ai": cfg, "abilities": [dmg_ability("poke", "1"), dmg_ability("heavy", "2")]})
	var eng := engine([a, _dummy("b", "B", {"stats": {"SPD": 1, "HP": 99999}})], 1, {"victory": {"limits": {"max_turns": 5, "stagnation_turns": 99}}})
	eng.run()
	var used: Array = events(eng, EventTypes.ACTION_SELECTED).filter(func(e): return e["source"] == "a").map(func(e): return e["data"]["ability"])
	assert_eq(used, ["poke", "poke", "heavy", "heavy", "heavy"])
	var sel := events(eng, EventTypes.ACTION_SELECTED).filter(func(e): return e["source"] == "a")
	assert_eq(sel[2]["data"]["details"]["transition"], {"from": "s1", "to": "s2", "rule": 0})
	assert_true(sel[2]["data"].has("memory_ops"), "el cambio de estado queda trazado")


# --- reacciones ------------------------------------------------------------------------------------

func _reactor(policy: Variant) -> Array:
	var counter := dmg_ability("counter", "1", {"action_type": "reaction", "trigger": {"event": "damage_dealt",
		"when": {"event.target": {"eq": "self"}}, "target": "event_source"}})
	var a := ent("a", "A", {"stats": {"SPD": 100, "ACC": 1.0}, "ai": {"type": "priority_list", "rules": [{"ability": "smack"}]}, "abilities": [dmg_ability("smack", "30")]})
	var ai: Dictionary = {"type": "passive"}
	if policy != null:
		ai["reactions"] = policy
	var b := ent("b", "B", {"stats": {"SPD": 1, "HP": 100}, "ai": ai, "abilities": [counter]})
	return [a, b]


func test_reaction_policy_default_allows_and_rules_decide() -> void:
	var free := engine(_reactor(null), 1, {"victory": {"limits": {"max_turns": 3, "stagnation_turns": 99}}})
	free.run()
	assert_eq(events(free, EventTypes.REACTION_TRIGGERED).size(), 3, "sin politica reacciona siempre")
	assert_eq(events(free, EventTypes.REACTION_DECLINED).size(), 0)
	var pol := {"default": "decline", "rules": [{"ability": "counter", "decision": "allow", "when": {"self.hp_ratio": {"lt": 0.5}}}]}
	var eng := engine(_reactor(pol), 1, {"victory": {"limits": {"max_turns": 3, "stagnation_turns": 99}}})
	eng.run()
	var declined := events(eng, EventTypes.REACTION_DECLINED)
	var fired := events(eng, EventTypes.REACTION_TRIGGERED)
	assert_eq(declined.size(), 1, "vida 70%%: se declina")
	assert_eq(declined[0]["data"]["reason"], "default")
	assert_eq(declined[0]["data"]["ability"], "counter")
	assert_eq(fired.size(), 2, "vida 40%% y 10%%: reacciona (regla 0)")
	check_causality(eng)


func test_declined_reaction_consumes_no_rng_or_resources() -> void:
	var chance_counter := dmg_ability("counter", "1", {"action_type": "reaction", "cost": {"mana": 10}, "trigger": {"event": "damage_dealt",
		"when": {"event.target": {"eq": "self"}}, "target": "event_source", "chance": 0.5}})
	var a := ent("a", "A", {"stats": {"SPD": 100, "ACC": 1.0}, "ai": {"type": "priority_list", "rules": [{"ability": "smack"}]}, "abilities": [dmg_ability("smack", "5")]})
	var b := ent("b", "B", {"stats": {"SPD": 1, "HP": 100}, "resources": _mana(), "ai": {"type": "passive", "reactions": {"default": "decline"}}, "abilities": [chance_counter]})
	var eng := engine([a, b], 1, {"victory": {"limits": {"max_turns": 3, "stagnation_turns": 99}}})
	eng.run()
	assert_eq(events(eng, EventTypes.PROC).size(), 0, "declinar ocurre antes de la tirada")
	assert_eq(events(eng, EventTypes.REACTION_TRIGGERED).size(), 0)
	assert_almost((b.get_resource("mana") as ResourceState).value, 100.0)
	assert_eq(events(eng, EventTypes.REACTION_DECLINED).size(), 3)


func test_reaction_condition_sees_event_amount_and_prediction() -> void:
	var pol := {"default": "decline", "rules": [{"ability": "counter", "decision": "allow", "when": {"event.amount": {"ge": 25}, "predict.damage": {"ge": 1}}}]}
	var eng := engine(_reactor(pol), 1, {"victory": {"limits": {"max_turns": 2, "stagnation_turns": 99}}})
	eng.run()
	assert_eq(events(eng, EventTypes.REACTION_TRIGGERED).size(), 2)


# --- privacidad ------------------------------------------------------------------------------------

func test_view_never_exposes_enemy_hidden_data_even_with_new_features() -> void:
	var a := ent("a", "A", {"stats": {"SPD": 100}, "ai": {"type": "scored", "weights": {"damage": 1}}, "abilities": [_phys("hit", "10")]})
	var b := _dummy("b", "B", {"stats": {"SPD": 40, "HP": 5000, "DEF": 7771, "ATK": 5551, "EVA": 0.3217},
		"abilities": [dmg_ability("secret_move", "1")], "tags": ["boss_secreto"]})
	b.ai_memory["x"] = "secreto_ia"
	var spy := _Spy.new(a.ai)
	a.ai = spy
	var eng := engine([a, b], 1, {"victory": {"limits": {"max_turns": 3, "stagnation_turns": 99}}})
	b.ai_memory["x"] = "secreto_ia"
	eng.run()
	assert_true(spy.views.size() > 0)
	for v in spy.views:
		var text := JSON.stringify(v)
		for leak in ["7771", "5551", "0.3217", "secret_move", "secreto_ia", "boss_secreto"]:
			assert_false(text.contains(leak), "la vista no debe filtrar '%s'" % leak)
		assert_false((v["others"][0] as Dictionary).has("stats"))
		assert_false((v["others"][0] as Dictionary).has("abilities"))
	# lo observado si llega, pero solo como resultado: razon de mitigacion, no la DEF
	var last: Dictionary = spy.views[spy.views.size() - 1]
	assert_true(last["self"]["memory"]["obs"].has("b"))
	assert_false(JSON.stringify(last["self"]["memory"]).contains("7771"))


func test_visible_fields_restrict_conditions_unknown_means_false() -> void:
	var cfg := {"type": "priority_list", "rules": [{"ability": "chip", "when": {"target.hp_ratio": {"lt": 2}}}]}
	var a := ent("a", "A", {"stats": {"SPD": 100}, "ai": cfg, "abilities": [dmg_ability("chip", "1")]})
	var eng := engine([a, _dummy()], 1, {"ai": {"visible_fields": ["initiative"]}})
	assert_eq(_decide(eng, "a").kind, AIDecision.Kind.WAIT, "vida del rival oculta: la condicion no se cumple")


# --- validacion ------------------------------------------------------------------------------------

func test_invalid_ai_configs_are_rejected_with_clear_errors() -> void:
	var cases := {
		"peso desconocido": [{"type": "scored", "weights": {"magia": 1}}, "caracteristica desconocida"],
		"peso no numerico": [{"type": "scored", "weights": {"damage": "mucho"}}, "numerico"],
		"clave desconocida": [{"type": "scored", "foo": 1}, "propiedad desconocida"],
		"estado inicial": [{"type": "state_machine", "initial": "x", "states": {"a": {"strategy": {"type": "passive"}}}}, "initial"],
		"anidada": [{"type": "state_machine", "initial": "a", "states": {"a": {"strategy": {"type": "state_machine", "initial": "a", "states": {}}}}}, "no puede ser state_machine"],
		"transicion": [{"type": "state_machine", "initial": "a", "states": {"a": {"strategy": {"type": "passive"}, "transitions": [{"to": "zz"}]}}}, "'to'"],
		"ruta": [{"type": "priority_list", "rules": [{"ability": "x", "when": {"enemy.stats.DEF": {"gt": 1}}}]}, "ruta desconocida"],
		"ruta de estado": [{"type": "scored", "modifiers": [{"when": {"target.hp": {"lt": 1}}}]}, "ruta desconocida"],
		"comparador": [{"type": "priority_list", "rules": [{"ability": "x", "when": {"self.hp": {"~": 1}}}]}, "comparador"],
		"remember": [{"type": "priority_list", "rules": [{"ability": "x", "remember": {"set": {"a": [1]}}}]}, "no permitido"],
		"reaccion": [{"type": "passive", "reactions": {"default": "quiza"}}, "allow|decline"],
		"reaccion evento": [{"type": "passive", "reactions": {"rules": [{"ability": "c", "when": {"event.type": {"eq": 1}}}]}}, "ruta desconocida"],
		"tipo": [{"type": "neuronal"}, "tipo desconocido"],
	}
	for k in cases:
		var res := AIFactory.build(cases[k][0])
		assert_true(res["ai"] == null and res["errors"].size() > 0, "debe rechazar: %s" % k)
		assert_contains(" ".join(res["errors"]), cases[k][1], k)
	for ok in [{"type": "passive"}, {"type": "scored"}, {"type": "priority_list", "rules": []}, _machine()]:
		assert_eq(AIFactory.build(ok)["errors"], [], JSON.stringify(ok))


func test_entity_factory_rejects_ai_referencing_unknown_abilities() -> void:
	for cfg in [{"type": "scored", "bias": {"fantasma": 1}}, {"type": "scored", "exclude": ["fantasma"]},
			{"type": "passive", "reactions": {"rules": [{"ability": "fantasma"}]}},
			{"type": "state_machine", "initial": "a", "states": {"a": {"strategy": {"type": "priority_list", "rules": [{"ability": "fantasma"}]}}}}]:
		var b := EntityFactory.build({"id": "x", "team": "A", "basic_attack": false, "ai": cfg}, BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())
		assert_true(b["errors"].size() > 0, JSON.stringify(cfg))
		assert_contains(" ".join(b["errors"]), "fantasma")


func test_ai_schema_validates_new_types_in_packages() -> void:
	var v := SchemaValidator.new()
	var good: Dictionary = JSON.parse_string(FileAccess.get_file_as_string(PKG + "ai.json"))
	assert_eq(v.validate("ai.schema.json", good), [], "el paquete de perfiles cumple el esquema publico")
	var bad: Dictionary = good.duplicate(true)
	bad["strategies"]["aggressive"]["weights"]["damage"] = "mucho"
	assert_true(v.validate("ai.schema.json", bad).size() > 0)
	var bad2: Dictionary = good.duplicate(true)
	bad2["strategies"]["adaptive"]["states"]["attack"]["strategy"]["type"] = "state_machine"
	assert_true(v.validate("ai.schema.json", bad2).size() > 0, "sin anidar maquinas")


# --- perfiles intercambiables ----------------------------------------------------------------------

func _profiles() -> Dictionary:
	return JSON.parse_string(FileAccess.get_file_as_string(PKG + "ai.json"))["strategies"]


func _fighter(id: String, team: String, ai: Dictionary, hp: int = 700) -> CombatEntity:
	return ent(id, team, {"stats": {"SPD": 100, "HP": hp, "ATK": 90, "ACC": 0.9, "CRIT": 0.1}, "resources": _mana(), "ai": ai, "abilities": [
		dmg_ability("strike", "55", {"effects": [{"type": "damage", "components": [{"damage_type": "physical", "formula": "caster.ATK * 0.6 + 4"}]}]}),
		dmg_ability("heavy", "140", {"cost": {"mana": 40}, "effects": [{"type": "damage", "components": [{"damage_type": "physical", "formula": "caster.ATK * 1.7"}]}]}),
		{"id": "mend", "targeting": "self", "cost": {"mana": 30}, "effects": [{"type": "heal", "formula": "120"}]}]})


func _duel(ai_a: Dictionary, ai_b: Dictionary, seed_value: int) -> CombatEngine:
	var eng := engine([_fighter("a", "A", ai_a), _fighter("b", "B", ai_b)], seed_value, {"victory": {"limits": {"max_turns": 60, "stagnation_turns": 99}}})
	eng.run()
	return eng


func test_all_profiles_build_and_run_deterministically() -> void:
	var profs := _profiles()
	assert_eq(profs.keys().size(), 6)
	for want in ["aggressive", "defensive", "balanced", "conservative", "opportunistic", "adaptive"]:
		assert_true(profs.has(want), want)
		assert_eq(AIFactory.build(profs[want])["errors"], [], want)
	for name in profs:
		var h1 := _duel(profs[name], profs["balanced"], 7).result.log_hash
		var h2 := _duel(profs[name], profs["balanced"], 7).result.log_hash
		assert_eq(h1, h2, "%s: misma semilla, mismo combate" % name)


func test_profiles_are_interchangeable_and_behave_differently() -> void:
	var profs := _profiles()
	var seqs := {}
	for name in profs:
		var eng := _duel(profs[name], {"type": "priority_list", "rules": [{"ability": "strike"}]}, 5)
		seqs[name] = events(eng, EventTypes.ACTION_SELECTED).filter(func(e): return e["source"] == "a").map(func(e): return e["data"]["ability"] if e["data"]["kind"] == "ability" else "wait")
		assert_true(seqs[name].size() > 0, name)
	var distinct := {}
	for name in seqs:
		distinct[",".join(seqs[name])] = true
	assert_true(distinct.size() >= 3, "los perfiles producen comportamientos distintos (%d)" % distinct.size())
	assert_true(seqs["defensive"].has("mend"), "el defensivo cura")
	assert_false(seqs["aggressive"].has("wait"))
	# cambiar la IA no altera la construccion del personaje (mismo contenido)
	var e1 := _fighter("a", "A", profs["aggressive"])
	var e2 := _fighter("a", "A", profs["defensive"])
	assert_eq(e1.abilities.map(func(x): return x.id), e2.abilities.map(func(x): return x.id))
	assert_eq(e1.stats.effective_map(), e2.stats.effective_map())


func test_profile_comparison_is_free_of_creation_points() -> void:
	# comparar perfiles no requiere ni afecta a la valoracion (PROJECT.md 10.1): la IA no entra en el coste
	var profs := _profiles()
	var a1 := _fighter("a", "A", profs["aggressive"])
	var a2 := _fighter("a", "A", profs["conservative"])
	assert_eq(JSON.stringify(a1.stats.effective_map()), JSON.stringify(a2.stats.effective_map()))


func test_ai_profiles_package_imports_and_drives_a_character() -> void:
	var tmp := "user://_tests_phase4/t%d" % Time.get_ticks_usec()
	var lib := ContentLibrary.new(tmp + "/lib")
	var imp := PackageImporter.new(lib)
	var rep := imp.import_package(PKG.rstrip("/"))
	assert_true(rep.ok(), "\n".join(rep.errors))
	var spells := imp.import_package("res://content/packages/core_spells")
	assert_true(spells.ok(), "\n".join(spells.errors))
	var d := tmp + "/hero"
	DirAccess.make_dir_recursive_absolute(d)
	var files := {"resources.json": JSON.stringify({"schema": "simhalla.resources/1", "resources": {"mana": {"initial": 80, "min": 0, "max": 80}}}),
		"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": "t/caster", "version": "1.0.0", "type": "character", "name": "T",
			"dependencies": [{"id": "examples/core_spells", "version": "^1.0.0"}, {"id": "examples/ai_profiles", "version": "^1.0.0"}]}),
		"character.json": JSON.stringify({"schema": "simhalla.character/1", "name": "Caster", "stats": {"HP": 600, "MAG": 150, "SPD": 110}, "basic_attack": true,
			"imports": [{"package": "examples/core_spells", "version": "^1.0.0", "abilities": ["fireball", "mend"]}],
			"ai_ref": {"package": "examples/ai_profiles", "version": "^1.0.0", "strategy": "opportunistic"}})}
	for rel in files:
		var f := FileAccess.open(d.path_join(rel), FileAccess.WRITE)
		f.store_string(files[rel])
		f.close()
	var hero := imp.import_package(d)
	assert_true(hero.ok(), "\n".join(hero.errors))
	var out := DuelRunner.run({"seed": 4, "library": lib.root, "entities": [
		{"package": "t/caster", "overrides": {"team": "A"}}, {"package": "t/caster", "overrides": {"id": "other", "team": "B"}}]})
	assert_true(out["ok"], str(out["errors"]))
	var eng: CombatEngine = out["engine"]
	assert_eq(eng.get_entity("t/caster").ai.ai_id(), "scored")
	ContentLibrary._remove_tree("user://_tests_phase4")


# --- arboles de comportamiento ---------------------------------------------------------------------

func _tree() -> Dictionary:
	return {"type": "behavior_tree", "root": {"type": "selector", "children": [
		{"type": "sequence", "children": [
			{"type": "condition", "when": {"self.hp_ratio": {"lt": 0.4}}},
			{"type": "action", "ability": "mend", "target": "self", "remember": {"incr": {"heals": 1}}}]},
		{"type": "sequence", "children": [
			{"type": "condition", "when": {"mem.opened": {"eq": 0}}},
			{"type": "action", "ability": "opener", "remember": {"set": {"opened": 1}}}]},
		{"type": "strategy", "strategy": {"type": "scored", "weights": {"damage": 1}}},
		{"type": "wait", "reason": "nada"}]}}


func _tree_fighter(cfg: Dictionary) -> CombatEntity:
	return ent("a", "A", {"stats": {"SPD": 100, "HP": 400}, "ai": cfg, "abilities": [dmg_ability("chip", "10"), dmg_ability("opener", "5"),
		{"id": "mend", "targeting": "self", "effects": [{"type": "heal", "formula": "100"}]}]})


func test_behavior_tree_ticks_guards_actions_strategies_and_memory() -> void:
	var eng := engine([_tree_fighter(_tree()), _dummy()])
	var a := eng.get_entity("a")
	var d1 := _decide(eng, "a")
	assert_eq(d1.ability_id, "opener")
	assert_eq(d1.reason, "bt:root.children[1].children[1]")
	assert_eq(d1.details["tree"][0], {"node": "root.children[0].children[0]", "ok": false}, "traza del recorrido")
	var d2 := _decide(eng, "a")
	assert_eq(d2.ability_id, "chip", "la memoria cierra la apertura y delega en la estrategia puntuada")
	assert_true(d2.reason.begins_with("bt:root.children[2]/"))
	hit(eng, eng.get_entity("t"), a, 300.0)
	var d3 := _decide(eng, "a")
	assert_eq(d3.ability_id, "mend", "la guarda de vida baja tiene prioridad")
	assert_almost(float(a.ai_memory["vars"]["heals"]), 1.0)


func test_behavior_tree_wait_not_succeed_and_empty_tick() -> void:
	var cfg := {"type": "behavior_tree", "root": {"type": "selector", "children": [
		{"type": "sequence", "children": [{"type": "not", "child": {"type": "condition", "when": {"enemy.alive_count": {"ge": 1}}}},
			{"type": "action", "ability": "chip"}]},
		{"type": "succeed", "child": {"type": "action", "ability": "nada_legal_aqui"}}]}}
	var a := ent("a", "A", {"stats": {"SPD": 100}, "ai": cfg, "abilities": [dmg_ability("chip", "1"), dmg_ability("nada_legal_aqui", "1", {"cost": {"mana": 999}})],
		"resources": _mana()})
	var eng := engine([a, _dummy()])
	var d := _decide(eng, "a")
	assert_eq(d.kind, AIDecision.Kind.WAIT)
	assert_eq(d.reason, "bt_no_decision", "hay enemigos: la guarda 'not' falla; la accion no es legal")
	var w := engine([_tree_fighter({"type": "behavior_tree", "root": {"type": "wait", "reason": "reservo"}}), _dummy()])
	assert_eq(_decide(w, "a").reason, "reservo")


func test_behavior_tree_validation_and_limits() -> void:
	var deep: Dictionary = {"type": "wait"}
	for i in 9:
		deep = {"type": "succeed", "child": deep}
	var many: Array = []
	for i in 70:
		many.append({"type": "wait"})
	var cases := {
		"sin root": [{"type": "behavior_tree"}, "root"],
		"nodo desconocido": [{"type": "behavior_tree", "root": {"type": "loop"}}, "tipo de nodo"],
		"children vacio": [{"type": "behavior_tree", "root": {"type": "selector", "children": []}}, "children"],
		"propiedad": [{"type": "behavior_tree", "root": {"type": "wait", "x": 1}}, "propiedad desconocida"],
		"profundidad": [{"type": "behavior_tree", "root": deep}, "profundidad"],
		"nodos": [{"type": "behavior_tree", "root": {"type": "selector", "children": many}}, "nodos"],
		"condition sin when": [{"type": "behavior_tree", "root": {"type": "condition"}}, "when"],
		"estrategia anidada": [{"type": "behavior_tree", "root": {"type": "strategy", "strategy": {"type": "behavior_tree", "root": {"type": "wait"}}}}, "passive|priority_list|scored"],
		"accion": [{"type": "behavior_tree", "root": {"type": "action", "ability": "x", "target": "nadie"}}, "target desconocido"],
		"ruta": [{"type": "behavior_tree", "root": {"type": "condition", "when": {"target.hp": {"lt": 1}}}}, "ruta desconocida"],
	}
	for k in cases:
		var res := AIFactory.build(cases[k][0])
		assert_true(res["ai"] == null and res["errors"].size() > 0, "debe rechazar: %s" % k)
		assert_contains(" ".join(res["errors"]), cases[k][1], k)
	assert_eq(AIFactory.build(_tree())["errors"], [])
	# dentro de una maquina de estados y con referencias a habilidades inexistentes
	var sm := {"type": "state_machine", "initial": "a", "states": {"a": {"strategy": _tree()}}}
	assert_eq(AIFactory.build(sm)["errors"], [])
	var b := EntityFactory.build({"id": "x", "team": "A", "basic_attack": false, "ai": {"type": "behavior_tree", "root": {"type": "action", "ability": "fantasma"}}},
		BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())
	assert_contains(" ".join(b["errors"]), "fantasma")


func test_behavior_tree_runs_a_real_combat_deterministically() -> void:
	var run := func() -> String:
		var a := _tree_fighter(_tree())
		return engine([a, _dummy("t", "B", {"stats": {"SPD": 60, "HP": 300}})], 3, {"victory": {"limits": {"max_turns": 8, "stagnation_turns": 99}}}).run().log_hash
	assert_eq(run.call(), run.call())


func test_schema_accepts_trees_and_rejects_bad_nodes() -> void:
	var v := SchemaValidator.new()
	var ok := {"schema": "simhalla.ai/1", "strategies": {"t": _tree()}}
	assert_eq(v.validate("ai.schema.json", ok), [])
	var bad := {"schema": "simhalla.ai/1", "strategies": {"t": {"type": "behavior_tree", "root": {"type": "selector", "children": [{"type": "bogus"}]}}}}
	assert_true(v.validate("ai.schema.json", bad).size() > 0)


# --- predictor declarativo: time_to_turn / reactions_seen ----------------------------------------------

func test_time_to_turn_and_reactions_seen_are_usable_from_conditions_and_scores() -> void:
	var counter := dmg_ability("counter", "1", {"action_type": "reaction", "trigger": {"event": "damage_dealt",
		"when": {"event.target": {"eq": "self"}}, "target": "event_source"}})
	var cfg := {"type": "priority_list", "rules": [
		{"ability": "smack", "when": {"predict.reactions_seen": {"ge": 1}, "predict.time_to_turn": {"ge": 0}}, "remember": {"set": {"informed": 1}}},
		{"ability": "smack"}]}
	var a := ent("a", "A", {"stats": {"SPD": 100, "ACC": 1.0}, "ai": cfg, "abilities": [dmg_ability("smack", "5")]})
	var b := ent("b", "B", {"stats": {"SPD": 70, "HP": 99999}, "ai": {"type": "priority_list", "rules": [{"ability": "poke"}]}, "abilities": [counter, dmg_ability("poke", "1")]})
	var eng := engine([a, b], 2, {"victory": {"limits": {"max_turns": 8, "stagnation_turns": 99}}})
	var early := _view(eng, "a")
	assert_eq(AIPredictor.time_to_turn(early, "b"), null, "sin observar no hay estimacion")
	assert_false(AIConditions.holds({"predict.time_to_turn": {"ge": 0}}, {"view": early, "target": null, "predict": AIPredictor.evaluate(early, "smack", "b"), "event": null}), "dato desconocido = falso")
	eng.run()
	var late := _view(eng, "a")
	assert_true(AIPredictor.time_to_turn(late, "b") != null, "tras observar turnos del rival hay estimacion")
	assert_true(AIPredictor.seen_reactions(late, "b").has("counter"))
	assert_eq(a.ai_memory["vars"].get("informed", 0), 1, "la condicion declarativa llego a cumplirse")
	var sc := ScoredAI.from_dict({"weights": {"tempo": 2, "reaction_risk": -3}})
	var cand := sc._features(late, "smack", "b", PriorityListAI._entity(late, "b"), late["self"]["abilities"][0])
	assert_eq(cand["reaction_risk"], 1.0)
	assert_true(cand["tempo"] >= 0.0 and cand["tempo"] <= 1.0)


# --- reglas del artefacto sobre cualquier IA ---------------------------------------------------------------

func _artifact_ent(cfg: Dictionary) -> Dictionary:
	return EntityFactory.build({"id": "r", "team": "A", "basic_attack": false, "stats": {"SPD": 100}, "ai": cfg, "abilities": [dmg_ability("chip", "10"), dmg_ability("zap", "3")],
		"artifact": {"id": "rod", "ai_rules": [{"ability": "zap", "target": "first_enemy", "when": {"mem.zapped": {"eq": 0}}, "remember": {"set": {"zapped": 1}}}]}},
		BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())


func test_artifact_ai_rules_overlay_scored_state_machine_and_tree() -> void:
	for cfg in [{"type": "scored", "weights": {"damage": 1}}, _machine_like(), {"type": "behavior_tree", "root": {"type": "strategy", "strategy": {"type": "scored", "weights": {"damage": 1}}}}]:
		var b := _artifact_ent(cfg)
		assert_eq(b["errors"], [], str(cfg["type"]))
		var e: CombatEntity = b["entity"]
		assert_true(e.ai is OverlayAI)
		var eng := engine([e, _dummy()])
		var d1 := _decide(eng, "r")
		assert_eq(d1.ability_id, "zap", "la regla del artefacto gana")
		assert_eq(d1.reason, "artifact_rule_0")
		var d2 := _decide(eng, "r")
		assert_eq(d2.ability_id, "chip", "tras recordar, decide la IA base (%s)" % str(cfg["type"]))
		assert_false(d2.details["artifact_rules_discarded"].is_empty())
	var ghost := EntityFactory.build({"id": "r", "team": "A", "basic_attack": false, "ai": {"type": "scored"},
		"artifact": {"id": "rod", "ai_rules": [{"ability": "nada"}]}}, BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())
	assert_contains(" ".join(ghost["errors"]), "inexistente")
	var passive := EntityFactory.build({"id": "r", "team": "A", "basic_attack": false, "ai": {"type": "passive"}, "abilities": [dmg_ability("zap", "1")],
		"artifact": {"id": "rod", "ai_rules": [{"ability": "zap"}]}}, BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())
	assert_contains(" ".join(passive["errors"]), "priority_list")


func _machine_like() -> Dictionary:
	return {"type": "state_machine", "initial": "s", "states": {"s": {"strategy": {"type": "scored", "weights": {"damage": 1}}}}}
