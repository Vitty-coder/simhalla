extends Phase3Case
## Fase 3.2: defensas nativas (escudos, reduccion, inmunidad, parada, bloqueo, reflejo,
## prevencion de muerte, absorcion elemental) y reacciones / habilidades disparadas.

func _two(a_data: Dictionary = {}, b_data: Dictionary = {}, over: Dictionary = {}, seed_value: int = 1) -> CombatEngine:
	var a := ent("a", "A", a_data)
	var b := ent("b", "B", b_data)
	var eng := engine([a, b], seed_value, over)
	eng.start()
	return eng


func _ward(defense: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var d := {"id": "ward", "duration": {"unit": "permanent"}, "beneficial": true, "defense": defense}
	d.merge(extra, true)
	return d


# --- defensas -------------------------------------------------------------------------------------

func test_shield_absorbs_then_breaks_with_trace() -> void:
	var eng := _two({}, {"statuses": [_ward({"absorb": {"amount": "100"}})]})
	var a := eng.get_entity("a")
	var b := eng.get_entity("b")
	eng.status_service.apply("ward", b, b)
	hit(eng, a, b, 60.0)
	assert_almost(b.hp, 1000.0, 1e-9, "60 absorbidos")
	assert_almost(b.statuses[0].shield, 40.0)
	hit(eng, a, b, 70.0)
	assert_almost(b.hp, 970.0, 1e-9, "40 absorbidos, 30 pasan")
	assert_eq(b.statuses.size(), 0, "escudo agotado = estado retirado")
	var rem := events(eng, EventTypes.STATUS_REMOVED)
	assert_eq(rem[0]["data"]["reason"], "depleted")
	var mods := events(eng, EventTypes.EVENT_MODIFIED)
	assert_eq(mods.size(), 2)
	assert_eq(mods[0]["source"], "status:ward", "el origen de la mitigacion queda registrado")
	var dealt := events(eng, EventTypes.DAMAGE_DEALT)
	assert_almost(dealt[1]["data"]["intended"], 70.0, 1e-9, "dano intentado")
	assert_almost(dealt[1]["data"]["mitigated"], 40.0, 1e-9, "mitigado por el escudo")
	assert_almost(dealt[1]["data"]["amount"], 30.0)
	check_causality(eng)


func test_shield_filters_by_type_and_element() -> void:
	var eng := _two({}, {"statuses": [_ward({"absorb": {"amount": "100", "elements": ["fire"]}})]})
	var a := eng.get_entity("a")
	var b := eng.get_entity("b")
	eng.status_service.apply("ward", b, b)
	hit(eng, a, b, 50.0, "true", "ice")
	assert_almost(b.hp, 950.0, 1e-9, "hielo no lo absorbe")
	hit(eng, a, b, 50.0, "true", "fire")
	assert_almost(b.hp, 950.0, 1e-9, "fuego si")


func test_reduction_pct_then_flat_with_type_filter() -> void:
	var eng := _two({}, {"statuses": [_ward({"reduction": {"pct": 0.5, "flat": 10, "damage_types": ["physical"]}})]})
	var a := eng.get_entity("a")
	var b := eng.get_entity("b")
	eng.status_service.apply("ward", b, b)
	hit(eng, a, b, 100.0, "physical")
	assert_almost(b.hp, 1000.0 - 40.0, 1e-9, "100*0.5-10 = 40")
	hit(eng, a, b, 100.0, "magical")
	assert_almost(b.hp, 1000.0 - 40.0 - 100.0, 1e-9, "magico no se reduce")
	hit(eng, a, b, 15.0, "physical")
	assert_almost(b.hp, 860.0, 1e-9, "no baja de 0: 15*0.5-10 < 0")


func test_immunity_to_type_and_element() -> void:
	var eng := _two({}, {"statuses": [_ward({"immune_damage_types": ["magical"], "immune_elements": ["fire"]})]})
	var a := eng.get_entity("a")
	var b := eng.get_entity("b")
	eng.status_service.apply("ward", b, b)
	hit(eng, a, b, 100.0, "magical")
	hit(eng, a, b, 100.0, "physical", "fire")
	assert_almost(b.hp, 1000.0)
	hit(eng, a, b, 100.0, "physical", "ice")
	assert_almost(b.hp, 900.0)


func test_elemental_absorption_heals() -> void:
	var eng := _two({}, {"statuses": [_ward({"absorb_elements": ["fire"]})]})
	var a := eng.get_entity("a")
	var b := eng.get_entity("b")
	eng.status_service.apply("ward", b, b)
	b.hp = 500.0
	hit(eng, a, b, 120.0, "magical", "fire")
	assert_almost(b.hp, 620.0, 1e-9, "el fuego se convierte en curacion")
	assert_eq(events(eng, EventTypes.DAMAGE_DEALT).size(), 0)
	var heal: Dictionary = events(eng, EventTypes.HEAL_DONE)[0]
	assert_eq(heal["data"]["reason"], "elemental_absorb")


func test_parry_and_block() -> void:
	var always := _two({}, {"statuses": [_ward({"parry": {"chance": 1.0}})]})
	hit(always, always.get_entity("a"), always.get_entity("b"), 100.0)
	always.status_service.apply("ward", always.get_entity("b"), always.get_entity("b"))
	hit(always, always.get_entity("a"), always.get_entity("b"), 100.0)
	assert_almost(always.get_entity("b").hp, 900.0, 1e-9, "el primero (sin estado) entra; el segundo es parado")
	assert_eq(events(always, EventTypes.EVENT_CANCELLED).size(), 1)
	var never := _two({}, {"statuses": [_ward({"parry": {"chance": 0.0}})]})
	never.status_service.apply("ward", never.get_entity("b"), never.get_entity("b"))
	hit(never, never.get_entity("a"), never.get_entity("b"), 100.0)
	assert_almost(never.get_entity("b").hp, 900.0)
	var blk := _two({}, {"statuses": [_ward({"block": {"chance": 1.0, "pct": 0.75}})]})
	blk.status_service.apply("ward", blk.get_entity("b"), blk.get_entity("b"))
	hit(blk, blk.get_entity("a"), blk.get_entity("b"), 100.0)
	assert_almost(blk.get_entity("b").hp, 975.0)
	assert_true(events(blk, EventTypes.PROC).size() >= 1, "las tiradas de bloqueo quedan registradas")


func test_reflect_does_not_chain() -> void:
	var a := ent("a", "A", {"statuses": [_ward({"reflect": {"pct": 0.5}})]})
	var b := ent("b", "B", {"statuses": [_ward({"reflect": {"pct": 0.5}})]})
	var eng := engine([a, b])
	eng.start()
	eng.status_service.apply("ward", a, a)
	eng.status_service.apply("ward", b, b)
	hit(eng, a, b, 100.0)
	assert_almost(b.hp, 900.0)
	assert_almost(a.hp, 950.0, 1e-9, "50 reflejados, y el reflejo no se vuelve a reflejar")
	var dealt := events(eng, EventTypes.DAMAGE_DEALT)
	assert_eq(dealt.size(), 2)
	assert_true(dealt[1]["data"]["reflected"])
	assert_eq(dealt[1]["source"], "b")


func test_reflect_can_kill_attacker_simultaneous_with_target() -> void:
	var a := ent("a", "A", {"stats": {"HP": 40, "SPD": 200, "ACC": 1.0}, "abilities": [dmg_ability("smash", "100")],
		"ai": {"type": "priority_list", "rules": [{"ability": "smash"}]}})
	var b := ent("b", "B", {"stats": {"HP": 40, "SPD": 1}, "statuses": [_ward({"reflect": {"pct": 1.0}})]})
	var eng := engine([a, b])
	eng.start()
	eng.status_service.apply("ward", b, b)
	var r := eng.run()
	assert_false(a.alive)
	assert_false(b.alive)
	assert_true(r.is_draw(), "ambos mueren en la misma accion: empate")
	assert_eq(r.reason, "simultaneous_death")


func test_prevent_death_is_consumed() -> void:
	var eng := _two({}, {"statuses": [_ward({"prevent_death": {"survive_hp": 50}})]})
	var a := eng.get_entity("a")
	var b := eng.get_entity("b")
	eng.status_service.apply("ward", b, b)
	hit(eng, a, b, 5000.0)
	assert_true(b.alive)
	assert_almost(b.hp, 50.0)
	assert_eq(b.statuses.size(), 0, "se consume")
	hit(eng, a, b, 5000.0)
	assert_false(b.alive, "la segunda vez muere")
	assert_eq(events(eng, EventTypes.DEATH).size(), 1)


func test_defenses_are_not_free() -> void:
	var eng := _two()
	hit(eng, eng.get_entity("a"), eng.get_entity("b"), 100.0, "magical", "fire")
	assert_almost(eng.get_entity("b").hp, 900.0)
	assert_eq(events(eng, EventTypes.EVENT_MODIFIED).size(), 0)


func test_defense_order_immunity_then_shield_then_reduction() -> void:
	var def := {"id": "combo", "duration": {"unit": "permanent"}, "defense": {"reduction": {"pct": 0.5}, "absorb": {"amount": "20"}}}
	var eng := _two({}, {"statuses": [def]})
	eng.status_service.apply("combo", eng.get_entity("b"), eng.get_entity("b"))
	hit(eng, eng.get_entity("a"), eng.get_entity("b"), 100.0)
	# reduccion primero (100 -> 50), despues el escudo absorbe 20: 30 de dano
	assert_almost(eng.get_entity("b").hp, 970.0)


func test_defense_validation() -> void:
	var reg := OperationRegistry.new()
	for bad in [{"id": "x", "defense": {"absorb": {"amount": "1 +"}}}, {"id": "x", "defense": {"reduction": {"magia": 1}}},
			{"id": "x", "defense": {"immune_damage_types": ["psi"]}}, {"id": "x", "defense": {"absorb": 5}}]:
		assert_true(StatusDef.from_dict(bad, reg)["def"] == null, JSON.stringify(bad))


# --- reacciones -------------------------------------------------------------------------------------

func _counter(extra: Dictionary = {}) -> Dictionary:
	var d := dmg_ability("counter", "25", {"action_type": "reaction", "trigger": {"event": "damage_dealt",
		"when": {"event.target": {"eq": "self"}, "event.source": {"eq": "enemy"}}, "target": "event_source"}})
	d.merge(extra, true)
	return d


func test_counterattack_reaction_out_of_turn_with_causality() -> void:
	var a := ent("a", "A", {"basic_attack": true, "stats": {"ACC": 1.0, "SPD": 200, "CRIT": 0.0},
		"ai": {"type": "priority_list", "rules": [{"ability": "basic_attack"}]}})
	var b := ent("b", "B", {"stats": {"SPD": 1, "EVA": 0.0}, "abilities": [_counter()]})
	var eng := engine([a, b], 1, {"victory": {"limits": {"max_turns": 3}}})
	eng.run()
	var trig := events(eng, EventTypes.REACTION_TRIGGERED)
	assert_true(trig.size() >= 1)
	var first: Dictionary = trig[0]
	assert_eq(first["source"], "b")
	assert_eq(first["target"], "a")
	# la reaccion ocurre dentro del turno de a (fuera del turno propio de b)
	var cause := _find(eng, int(first["cause"]))
	assert_eq(cause["type"], EventTypes.DAMAGE_DEALT)
	var counter_hits := events(eng, EventTypes.DAMAGE_DEALT).filter(func(e): return e["source"] == "b")
	assert_almost(counter_hits[0]["data"]["amount"], 25.0)
	assert_eq(counter_hits[0]["time"], cause["time"], "mismo instante: reaccion inmediata")
	check_causality(eng)


func _find(eng: CombatEngine, id: int) -> Dictionary:
	for ev in eng.log.events:
		if int(ev["id"]) == id:
			return ev
	return {}


func test_reaction_pays_cost_and_respects_cooldown_and_limit_per_turn() -> void:
	var counter := _counter({"cost": {"mana": 5}, "cooldown": 2})
	var a := ent("a", "A", {"stats": {"SPD": 200, "ACC": 1.0, "CRIT": 0.0}, "basic_attack": true, "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack"}]}})
	var b := ent("b", "B", {"stats": {"SPD": 1, "EVA": 0.0, "HP": 5000}, "resources": {"mana": {"initial": 100, "max": 100}}, "abilities": [counter]})
	var eng := engine([a, b], 1, {"victory": {"limits": {"max_turns": 6, "stagnation_turns": 99}}})
	eng.run()
	var fired := events(eng, EventTypes.REACTION_TRIGGERED).size()
	var hits_on_b := events(eng, EventTypes.DAMAGE_DEALT).filter(func(e): return e["target"] == "b" and not e["data"]["reflected"]).size()
	assert_true(fired >= 1 and fired < hits_on_b, "el cooldown limita las reacciones: %d de %d" % [fired, hits_on_b])
	assert_almost((b.get_resource("mana") as ResourceState).value, 100.0 - 5.0 * fired)


func test_trigger_conditions_on_event_data() -> void:
	var crit_only := dmg_ability("on_crit", "10", {"action_type": "reaction", "trigger": {"event": "damage_dealt",
		"when": {"event.target": {"eq": "self"}, "event.crit": {"eq": true}}, "target": "event_source"}})
	var big_only := dmg_ability("on_big", "10", {"action_type": "reaction", "trigger": {"event": "damage_dealt",
		"when": {"event.target": {"eq": "self"}, "event.amount": {"ge": 100}}, "target": "event_source"}})
	var a := ent("a", "A")
	var b := ent("b", "B", {"abilities": [crit_only, big_only]})
	var eng := engine([a, b])
	eng.start()
	hit(eng, a, b, 50.0)
	assert_eq(events(eng, EventTypes.REACTION_TRIGGERED).size(), 0, "ni critico ni grande")
	hit(eng, a, b, 150.0)
	var abil := events(eng, EventTypes.REACTION_TRIGGERED).map(func(e): return e["data"]["ability"])
	assert_eq(abil, ["on_big"])


func test_trigger_chance_is_traced_and_deterministic() -> void:
	var lucky := dmg_ability("lucky", "1", {"action_type": "reaction", "trigger": {"event": "damage_dealt",
		"when": {"event.target": {"eq": "self"}}, "target": "event_source", "chance": 0.5}})
	var runs: Array = []
	for rep in 2:
		var a := ent("a", "A")
		var b := ent("b", "B", {"abilities": [lucky], "stats": {"HP": 100000}})
		var eng := engine([a, b], 11)
		eng.start()
		for i in 40:
			hit(eng, a, b, 1.0)
		var procs := events(eng, EventTypes.PROC)
		runs.append([procs.size(), events(eng, EventTypes.REACTION_TRIGGERED).size()])
		assert_eq(procs.size(), 40)
	assert_eq(runs[0], runs[1])
	assert_true(runs[0][1] > 5 and runs[0][1] < 35, str(runs[0]))


func test_last_words_reaction_while_dead() -> void:
	var revenge := dmg_ability("last_words", "77", {"action_type": "reaction", "trigger": {"event": "death",
		"when": {"event.target": {"eq": "self"}}, "target": "event_source", "while_dead": true}})
	var a := ent("a", "A")
	var b := ent("b", "B", {"abilities": [revenge], "stats": {"HP": 10}})
	var eng := engine([a, b])
	eng.start()
	hit(eng, a, b, 100.0)
	assert_false(b.alive)
	assert_almost(a.hp, 1000.0 - 77.0, 1e-9, "la reaccion de un muerto solo si while_dead")


func test_lethal_hit_reaction_policy() -> void:
	# D-043: al reaccionar a damage_dealt la vida ya esta aplicada, pero la entidad sigue
	# "viva" hasta resolverse la muerte. Puede reaccionar al golpe letal salvo que se lo prohiba
	# con la condicion self.hp > 0.
	var plain := ent("b", "B", {"abilities": [_counter()], "stats": {"HP": 10}})
	var a1 := ent("a", "A")
	var eng1 := engine([a1, plain])
	eng1.start()
	hit(eng1, a1, plain, 100.0)
	assert_eq(events(eng1, EventTypes.REACTION_TRIGGERED).size(), 1, "reaccion al golpe letal")
	assert_almost(a1.hp, 1000.0 - 25.0)
	assert_false(plain.alive, "y aun asi muere")
	var guarded_ab := _counter()
	guarded_ab["trigger"]["when"]["self.hp"] = {"gt": 0}
	var guarded := ent("b", "B", {"abilities": [guarded_ab], "stats": {"HP": 10}})
	var a2 := ent("a", "A")
	var eng2 := engine([a2, guarded])
	eng2.start()
	hit(eng2, a2, guarded, 100.0)
	assert_eq(events(eng2, EventTypes.REACTION_TRIGGERED).size(), 0, "con self.hp > 0 no reacciona al golpe letal")


func test_reaction_can_prevent_the_lethal_hit_outcome() -> void:
	# Una reaccion al golpe letal que cura a la entidad evita su muerte (la muerte se resuelve despues).
	var heal := {"id": "second_wind", "targeting": "self", "action_type": "reaction", "effects": [{"type": "heal", "formula": "300"}],
		"trigger": {"event": "damage_dealt", "when": {"event.target": {"eq": "self"}}}}
	var a := ent("a", "A")
	var b := ent("b", "B", {"abilities": [heal], "stats": {"HP": 100}})
	var eng := engine([a, b])
	eng.start()
	hit(eng, a, b, 100.0)
	assert_true(b.alive, "curado a tiempo, no muere")
	assert_almost(b.hp, 100.0)
	assert_eq(events(eng, EventTypes.DEATH).size(), 0)


func test_triggered_abilities_are_not_selectable() -> void:
	var counter := _counter()
	var b := ent("b", "B", {"abilities": [counter], "ai": {"type": "priority_list", "rules": [{"ability": "counter"}]}})
	var a := ent("a", "A")
	var eng := engine([a, b])
	eng.start()
	var view := ViewBuilder.build(eng, b, TurnState.new(b, 1))
	assert_eq(view["legal_actions"].size(), 0)
	assert_contains(ActionValidator.validate(eng, b, TurnState.new(b, 1), AIDecision.use("counter", ["a"])), "solo_reactiva")


func test_reaction_chain_is_bounded() -> void:
	# a y b contraatacan al ser golpeados por el otro: cadena infinita en teoria.
	var cnt := func(id: String) -> Dictionary:
		return dmg_ability("c_" + id, "1", {"action_type": "reaction", "trigger": {"event": "damage_dealt",
			"when": {"event.target": {"eq": "self"}}, "target": "event_source"}})
	var a := ent("a", "A", {"abilities": [cnt.call("a")], "stats": {"HP": 100000}})
	var b := ent("b", "B", {"abilities": [cnt.call("b")], "stats": {"HP": 100000}})
	var eng := engine([a, b], 1, {"safety": {"max_reaction_chain": 3}})
	eng.start()
	hit(eng, a, b, 1.0)
	assert_false(eng.is_aborted(), "la cadena se corta limpiamente")
	assert_true(events(eng, EventTypes.LIMIT_REACHED).any(func(e): return e["data"]["limit"] == "max_reaction_chain"))
	assert_eq(events(eng, EventTypes.REACTION_TRIGGERED).size(), 3)
	var r := eng.run()
	assert_false(r.is_aborted())


func test_automatic_ability_on_turn_start_and_combat_start() -> void:
	var regen_turn := {"id": "regen_turn", "targeting": "self", "action_type": "free", "effects": [{"type": "heal", "formula": "10"}],
		"trigger": {"event": "turn_started", "when": {"event.source": {"eq": "self"}}, "target": "self"}}
	var opening := {"id": "opening", "targeting": "self", "effects": [{"type": "apply_status", "status": "taunt"}],
		"trigger": {"event": "combat_started"}}
	var a := ent("a", "A", {"abilities": [regen_turn, opening], "stats": {"SPD": 100}})
	var eng := engine([a, ent("b", "B", {"stats": {"SPD": 1}})], 1, {"victory": {"limits": {"max_turns": 3, "stagnation_turns": 99}}})
	a.hp = 500.0
	eng.run()
	assert_true(a.hp > 500.0, "cura automatica al empezar sus turnos")
	assert_eq(events(eng, EventTypes.STATUS_APPLIED).size(), 1, "pasiva de inicio de combate")


func test_react_to_status_applied_cleanse() -> void:
	var cleanse := {"id": "cleanse", "targeting": "self", "action_type": "reaction", "effects": [{"type": "remove_status", "tags": ["cc"]}],
		"trigger": {"event": "status_gained", "when": {"event.target": {"eq": "self"}}, "target": "self"}}
	var a := ent("a", "A")
	var b := ent("b", "B", {"abilities": [cleanse]})
	var eng := engine([a, b])
	eng.start()
	eng.status_service.apply("stun", b, a)
	assert_eq(b.statuses.size(), 0, "se limpia al instante (inmunidad reactiva)")
	assert_eq(events(eng, EventTypes.STATUS_REMOVED).size(), 1)


func test_cancelled_pre_events_do_not_trigger_reactions() -> void:
	var counter := _counter()
	var a := ent("a", "A")
	var b := ent("b", "B", {"abilities": [counter]})
	var eng := engine([a, b])
	eng.start()
	eng.dispatcher.intercept(EventTypes.DAMAGE_PRE, func(ev: CombatEvent, _g): ev.cancel("barrera"), 0, "x")
	hit(eng, a, b, 50.0)
	assert_eq(events(eng, EventTypes.REACTION_TRIGGERED).size(), 0)


func test_reaction_can_be_interrupted_by_interceptor() -> void:
	var counter := _counter({"cost": {"mana": 10}})
	var a := ent("a", "A")
	var b := ent("b", "B", {"abilities": [counter], "resources": {"mana": {"initial": 50, "max": 50}}})
	var eng := engine([a, b])
	eng.start()
	eng.dispatcher.intercept(EventTypes.ACTION_STARTED, func(ev: CombatEvent, _g): if ev.source_id == "b": ev.cancel("silencio"), 0, "s")
	hit(eng, a, b, 50.0)
	assert_eq(events(eng, EventTypes.ACTION_INTERRUPTED).size(), 1)
	assert_almost((b.get_resource("mana") as ResourceState).value, 50.0, 1e-9, "interrumpida: no paga")


func test_trigger_validation() -> void:
	var reg := OperationRegistry.new()
	var bad := [
		{"id": "x", "trigger": {}}, {"id": "x", "trigger": {"event": "damage_dealt", "target": "nadie"}},
		{"id": "x", "trigger": {"event": "damage_dealt", "chance": 2}}, {"id": "x", "trigger": {"event": "damage_dealt", "limit_per_turn": 0}},
		{"id": "x", "trigger": {"event": "damage_dealt", "when": {"yo.hp": {"lt": 1}}}}, {"id": "x", "cast_time": 5, "trigger": {"event": "damage_dealt"}},
		{"id": "x", "trigger": {"event": "damage_dealt", "extra": 1}},
	]
	for d in bad:
		assert_true(AbilityDef.from_dict(d, reg)["ability"] == null, JSON.stringify(d))
	assert_true(AbilityDef.from_dict({"id": "ok", "trigger": {"event": "death", "when": {"event.target": {"eq": "self"}}}}, reg)["ability"] != null)
