extends Phase3Case
## Fase 3.3: invocaciones, formas (transformaciones), manipulacion temporal y escenarios combinados.

func _summoner(extra: Dictionary = {}, summon_effect: Dictionary = {}) -> CombatEntity:
	var eff := {"type": "summon", "template": "wolf"}
	eff.merge(summon_effect, true)
	var d := {"stats": {"SPD": 200, "HP": 3000, "ACC": 1.0},
		"abilities": [{"id": "call", "targeting": "self", "effects": [eff]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "call", "target": "self"}]},
		"summons": {"wolf": {"name": "Lobo", "stats": {"HP": 200, "ATK": 60, "SPD": 120, "ACC": 1.0}, "basic_attack": true}}}
	d.merge(extra, true)
	return ent("s", "A", d)


func _dummy(extra: Dictionary = {}) -> CombatEntity:
	var d := {"stats": {"SPD": 1, "HP": 9000, "EVA": 0.0}}
	d.merge(extra, true)
	return ent("t", "B", d)


# --- invocaciones ---------------------------------------------------------------------------------

func test_summon_creates_full_entity() -> void:
	var s := _summoner({}, {"inherit": {"stat_pct": {"ATK": 0.5}}})
	var eng := engine([s, _dummy()], 1, {"victory": {"limits": {"max_turns": 4}}})
	s.stats.set_base("ATK", 300.0)
	eng.run()
	var created := events(eng, EventTypes.SUMMON_CREATED)
	assert_true(created.size() >= 1)
	var wolf := eng.get_entity("s#wolf1")
	assert_true(wolf != null)
	assert_eq(wolf.owner_id, "s")
	assert_eq(wolf.team, "A", "mismo equipo que el invocador")
	assert_false(wolf.counts_for_victory)
	assert_almost(wolf.stats.get_value("ATK"), 150.0, 1e-9, "hereda 50 % del ATK del invocador")
	assert_almost(wolf.hp_max(), 200.0)
	assert_true(wolf.get_ability("basic_attack") != null, "entidad completa: habilidades propias")
	assert_true(events(eng, EventTypes.TURN_STARTED).any(func(e): return e["source"] == "s#wolf1"), "tiene su propia barra ATB y actua")
	assert_true(events(eng, EventTypes.DAMAGE_DEALT).any(func(e): return e["source"] == "s#wolf1" and e["target"] == "t"), "ataca con su IA")
	check_causality(eng)


func test_summon_validation_at_setup_and_in_template() -> void:
	var reg := OperationRegistry.new()
	assert_true(AbilityDef.from_dict({"id": "x", "effects": [{"type": "summon"}]}, reg)["ability"] == null)
	assert_true(AbilityDef.from_dict({"id": "x", "effects": [{"type": "summon", "template": "w", "count": 99}]}, reg)["ability"] == null)
	assert_true(AbilityDef.from_dict({"id": "x", "effects": [{"type": "summon", "template": "w", "lifespan": {"unit": "events", "amount": 1, "event": "hit"}}]}, reg)["ability"] == null)
	# plantilla inexistente
	var s := ent("s", "A", {"abilities": [{"id": "call", "effects": [{"type": "summon", "template": "fantasma"}]}]})
	var eng := CombatEngine.new()
	assert_contains(" ".join(eng.setup(Ruleset.from_dict({}), [s, _dummy()], 1)), "plantilla inexistente 'fantasma'")
	# plantilla con contenido invalido
	var b := EntityFactory.build({"id": "x", "team": "A", "summons": {"w": {"stats": {"HP": 0}}}}, BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())
	assert_true(b["entity"] == null)
	assert_contains(" ".join(b["errors"]), "summons.w")


func test_summon_limits_per_owner_and_total_do_not_abort() -> void:
	var s := _summoner({}, {"count": 5})
	var eng := engine([s, _dummy()], 1, {"summons": {"max_per_owner": 3, "max_entities": 64}, "victory": {"limits": {"max_turns": 6}}})
	var r := eng.run()
	assert_false(r.is_aborted())
	assert_eq(eng.owned_alive(s).size(), 3)
	assert_true(events(eng, EventTypes.LIMIT_REACHED).any(func(e): return e["data"].get("limit", "") == "summons_per_owner"))
	var s2 := _summoner({}, {"count": 8})
	var eng2 := engine([s2, _dummy()], 1, {"summons": {"max_per_owner": 8, "max_entities": 5}, "victory": {"limits": {"max_turns": 6}}})
	eng2.run()
	assert_eq(eng2.entities.size(), 5)
	assert_true(events(eng2, EventTypes.LIMIT_REACHED).any(func(e): return e["data"].get("limit", "") == "max_entities"))


func test_summon_lifespan_in_turns_and_time() -> void:
	var s := _summoner({}, {"lifespan": 2})
	var eng := engine([s, _dummy()], 1, {"victory": {"limits": {"max_turns": 40}}})
	eng.start()
	eng.run()
	var wolf := eng.get_entity("s#wolf1")
	assert_false(wolf.alive)
	var gone := events(eng, EventTypes.ENTITY_DESPAWNED).filter(func(e): return e["target"] == "s#wolf1")
	assert_eq(gone[0]["data"]["reason"], "lifespan")
	var wolf_turns := events(eng, EventTypes.TURN_STARTED).filter(func(e): return e["source"] == "s#wolf1").size()
	assert_eq(wolf_turns, 2, "vive exactamente 2 turnos propios")
	var s2 := _summoner({}, {"lifespan": {"unit": "time", "amount": 6}})
	var eng2 := engine([s2, _dummy()], 1, {"victory": {"limits": {"max_turns": 6}}})
	eng2.run()
	var g2 := events(eng2, EventTypes.ENTITY_DESPAWNED).filter(func(e): return e["target"] == "s#wolf1")
	assert_eq(g2[0]["time"], 5 * S + 6 * S, "invocada en t=5, desaparece en t=11")


func test_owner_death_despawns_or_stays_by_ruleset() -> void:
	for policy in ["despawn", "stay"]:
		var s := _summoner({"stats": {"SPD": 200, "HP": 100, "ACC": 1.0}})
		var t := _dummy({"stats": {"SPD": 60, "HP": 9000, "ATK": 5000, "ACC": 1.0}, "basic_attack": true, "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack", "target": "lowest_hp_enemy"}]}})
		var eng := engine([s, t], 1, {"summons": {"on_owner_death": policy}, "victory": {"limits": {"max_turns": 30}}})
		eng.run()
		if policy == "despawn":
			assert_false(eng.get_entity("s#wolf1").alive or false, "se va con su dueno")
			assert_true(events(eng, EventTypes.ENTITY_DESPAWNED).any(func(e): return e["data"]["reason"] == "owner_death"))
		else:
			assert_false(s.alive)


func test_summons_do_not_keep_team_alive() -> void:
	var s := _summoner({"stats": {"SPD": 200, "HP": 100, "ACC": 1.0}})
	var t := _dummy({"stats": {"SPD": 60, "HP": 9000, "ATK": 5000, "ACC": 1.0}, "basic_attack": true, "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack", "target": "first_enemy"}]}})
	var eng := engine([s, t], 1, {"summons": {"on_owner_death": "stay"}, "victory": {"limits": {"max_turns": 30}}})
	var r := eng.run()
	assert_true(r.is_win())
	assert_eq(r.winner_team, "B", "el dueno murio: el equipo A pierde aunque la invocacion siga viva")


func test_summon_depth_is_limited() -> void:
	# Una invocacion que a su vez invoca a su misma plantilla: la profundidad se corta (3).
	var tmpl := {"stats": {"HP": 100, "SPD": 400}, "abilities": [{"id": "call", "targeting": "self", "effects": [{"type": "summon", "template": "x"}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "call", "target": "self"}]}}
	tmpl["summons"] = {"x": {"stats": {"HP": 50, "SPD": 400}}}
	var s := ent("s", "A", {"stats": {"SPD": 200}, "summons": {"x": tmpl}, "abilities": [{"id": "call", "targeting": "self", "effects": [{"type": "summon", "template": "x"}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "call", "target": "self"}]}})
	var eng := engine([s, _dummy()], 1, {"summons": {"max_per_owner": 8, "max_entities": 40}, "victory": {"limits": {"max_turns": 30}}})
	var r := eng.run()
	assert_false(r.is_aborted())
	var depths: Array = eng.entities.map(func(e): return e.summon_depth)
	assert_true(depths.max() <= 3)


# --- formas (transformaciones) ---------------------------------------------------------------------

func _form_status(extra: Dictionary = {}) -> Dictionary:
	var d := {"id": "wolf_form", "group": "form", "duration": 2, "dispellable": true,
		"modifiers": [{"stat": "ATK", "kind": "flat", "value": 100}, {"stat": "ELEM_RES.fire", "kind": "flat", "value": 0.5, "per_stack": false}],
		"form": {"add_abilities": [dmg_ability("bite", "50")], "remove_abilities": ["spell"],
			"ai": {"type": "priority_list", "rules": [{"ability": "bite", "target": "lowest_hp_enemy"}]}}}
	d.merge(extra, true)
	return d


func _shifter() -> CombatEntity:
	return ent("s", "A", {"stats": {"SPD": 100, "ACC": 1.0}, "abilities": [dmg_ability("spell", "10")], "basic_attack": true,
		"statuses": [_form_status(), _form_status({"id": "bear_form", "form": {"add_abilities": [dmg_ability("maul", "90")]}, "modifiers": [{"stat": "DEF", "kind": "flat", "value": 80}]})],
		"ai": {"type": "priority_list", "rules": [{"ability": "spell"}]}})


func test_form_changes_stats_abilities_ai_and_reverts() -> void:
	var s := _shifter()
	var eng := engine([s, _dummy()])
	eng.start()
	var original_ai := s.ai
	eng.status_service.apply("wolf_form", s, s)
	assert_almost(s.stats.get_value("ATK"), 200.0)
	assert_almost(s.stats.get_value("ELEM_RES.fire"), 0.5)
	assert_true(s.get_ability("bite") != null)
	assert_true(s.get_ability("spell") == null, "se quita")
	assert_true(s.ai != original_ai, "IA sustituida")
	assert_eq(events(eng, EventTypes.TRANSFORMED).size(), 1)
	eng.status_service.dispel(s, {"status": "wolf_form"}, "test", 0)
	assert_almost(s.stats.get_value("ATK"), 100.0)
	assert_true(s.get_ability("bite") == null)
	assert_true(s.get_ability("spell") != null, "se restaura")
	assert_true(s.ai == original_ai, "IA original")
	assert_eq(events(eng, EventTypes.REVERTED).size(), 1)


func test_form_group_replaces_previous_form() -> void:
	var s := _shifter()
	var eng := engine([s, _dummy()])
	eng.start()
	eng.status_service.apply("wolf_form", s, s)
	eng.status_service.apply("bear_form", s, s)
	assert_eq(s.statuses.size(), 1)
	assert_eq(s.statuses[0].def.id, "bear_form")
	assert_true(s.get_ability("bite") == null and s.get_ability("maul") != null)
	assert_almost(s.stats.get_value("ATK"), 100.0, 1e-9, "los modificadores de la forma anterior se van")


func test_form_expires_and_is_used_in_combat() -> void:
	var s := _shifter()
	var shift := {"id": "shift", "targeting": "self", "uses_per_combat": 1, "effects": [{"type": "apply_status", "status": "wolf_form"}]}
	s.abilities.append(AbilityDef.from_dict(shift, OperationRegistry.new())["ability"])
	s.ai = PriorityListAI.from_dict({"rules": [{"ability": "shift", "target": "self"}, {"ability": "bite", "target": "lowest_hp_enemy"}, {"ability": "spell"}]})
	var eng := engine([s, _dummy()], 1, {"victory": {"limits": {"max_turns": 10, "stagnation_turns": 99}}})
	eng.run()
	var used := events(eng, EventTypes.ACTION_RESOLVED).filter(func(e): return e["source"] == "s").map(func(e): return e["data"]["ability"])
	assert_eq(used.slice(0, 3), ["shift", "bite", "bite"], "bajo la forma usa su nuevo repertorio")
	assert_true(used.has("spell") or used.size() < 5)
	assert_eq(events(eng, EventTypes.REVERTED).size(), 1)
	assert_true(s.get_ability("spell") != null)


func test_form_dies_with_entity() -> void:
	var s := _shifter()
	var eng := engine([s, _dummy()])
	eng.start()
	eng.status_service.apply("wolf_form", s, s)
	hit(eng, eng.get_entity("t"), s, 99999.0)
	assert_false(s.alive)
	assert_eq(s.statuses.size(), 0)
	assert_eq(events(eng, EventTypes.REVERTED).size(), 1)


# --- manipulacion temporal ---------------------------------------------------------------------------

func _tem(ops: Array, extra: Dictionary = {}) -> CombatEntity:
	var abilities: Array = []
	for o in ops:
		abilities.append(o)
	var d := {"abilities": abilities, "stats": {"SPD": 100, "ACC": 1.0}, "resources": {"mana": {"initial": 50, "max": 50}}}
	d.merge(extra, true)
	return ent("a", "A", d)


func _cast(eng: CombatEngine, caster: CombatEntity, ability: String, target: CombatEntity) -> void:
	ActionResolver.resolve(eng, TurnState.new(caster, 1), caster, caster.get_ability(ability), [target] as Array[CombatEntity], 0)


func test_record_and_restore_hp_and_resources_with_non_duplication() -> void:
	var rec := {"id": "rec", "targeting": "self", "effects": [{"type": "record_state", "key": "anchor"}]}
	var rst := {"id": "rst", "targeting": "self", "effects": [{"type": "restore_state", "key": "anchor"}]}
	var a := _tem([rec, rst])
	var eng := engine([a, _dummy()])
	eng.start()
	a.hp = 800.0
	_cast(eng, a, "rec", a)
	a.hp = 300.0
	(a.get_resource("mana") as ResourceState).value = 5.0
	var rng_before := eng.rng.get_states().duplicate()
	_cast(eng, a, "rst", a)
	assert_almost(a.hp, 800.0)
	assert_almost((a.get_resource("mana") as ResourceState).value, 50.0)
	assert_eq(eng.rng.get_states(), rng_before, "no se rebobina ni consume el RNG")
	assert_eq(events(eng, EventTypes.STATE_RESTORED).size(), 1)
	a.hp = 100.0
	_cast(eng, a, "rst", a)
	assert_almost(a.hp, 100.0, 1e-9, "no duplicable: la instantanea se consumio")
	assert_true(events(eng, EventTypes.TARGET_SKIPPED).any(func(e): return str(e["data"]["reason"]).begins_with("sin_estado_guardado")))
	assert_true(a.stored_states.is_empty())


func test_restore_selective_and_does_not_revive() -> void:
	var rec := {"id": "rec", "targeting": "self", "effects": [{"type": "record_state", "key": "k"}]}
	var rst_hp := {"id": "rst_hp", "targeting": "self", "effects": [{"type": "restore_state", "key": "k", "what": ["hp"], "consume": false}]}
	var a := _tem([rec, rst_hp])
	var eng := engine([a, _dummy()])
	eng.start()
	_cast(eng, a, "rec", a)
	a.hp = 10.0
	(a.get_resource("mana") as ResourceState).value = 7.0
	_cast(eng, a, "rst_hp", a)
	assert_almost(a.hp, 1000.0)
	assert_almost((a.get_resource("mana") as ResourceState).value, 7.0, 1e-9, "solo vida")
	assert_true(a.stored_states.has("k"), "consume:false conserva la instantanea")
	hit(eng, eng.get_entity("t"), a, 99999.0)
	assert_false(a.alive)
	_cast(eng, a, "rst_hp", a)
	assert_false(a.alive, "no revive a los muertos")
	assert_almost(a.hp, 0.0)


func test_delayed_effect_releases_later_and_skips_dead() -> void:
	var bomb := {"id": "bomb", "targeting": "enemy", "effects": [{"type": "delayed_effect", "delay": 4, "effects": [
		{"type": "damage", "always_hit": true, "can_crit": false, "components": [{"damage_type": "true", "formula": "200"}]}]}]}
	var a := _tem([bomb], {"stats": {"SPD": 200, "ACC": 1.0}, "ai": {"type": "priority_list", "rules": [{"ability": "bomb"}]}})
	var t := _dummy({"stats": {"SPD": 1, "HP": 9000}})
	var eng := engine([a, t], 1, {"victory": {"limits": {"max_turns": 2, "stagnation_turns": 99}}})
	eng.run()
	var sched := events(eng, EventTypes.DELAYED_SCHEDULED)
	var rel := events(eng, EventTypes.DELAYED_RELEASED)
	assert_true(sched.size() >= 1 and rel.size() >= 1)
	assert_eq(rel[0]["time"], sched[0]["time"] + 4 * S, "se libera exactamente 4 u.t. despues")
	var dealt: Dictionary = events(eng, EventTypes.DAMAGE_DEALT)[0]
	assert_eq(dealt["time"], rel[0]["time"])
	assert_almost(dealt["data"]["amount"], 200.0)
	check_causality(eng)
	# objetivo muerto antes de liberarse
	var a2 := _tem([bomb], {"stats": {"SPD": 200, "ACC": 1.0}, "ai": {"type": "priority_list", "rules": [{"ability": "bomb"}]}})
	var t2 := _dummy({"stats": {"SPD": 1, "HP": 9000}})
	var eng2 := engine([a2, t2], 1, {"victory": {"limits": {"max_turns": 1, "stagnation_turns": 99}}})
	eng2.scheduler.schedule(7 * S, func(e: CombatEngine): e.get_entity("t").hp = 0.0; e.check_all_deaths(), "kill")
	eng2.run()
	assert_eq(events(eng2, EventTypes.DAMAGE_DEALT).size(), 0, "objetivo muerto: no se aplica")


func test_delayed_kill_decides_victory_after_release() -> void:
	var bomb := {"id": "bomb", "targeting": "enemy", "effects": [{"type": "delayed_effect", "delay": 3, "effects": [
		{"type": "damage", "always_hit": true, "can_crit": false, "components": [{"damage_type": "true", "formula": "9999"}]}]}]}
	var a := _tem([bomb], {"stats": {"SPD": 200, "ACC": 1.0}, "ai": {"type": "priority_list", "rules": [{"ability": "bomb"}]}})
	var r := engine([a, _dummy({"stats": {"SPD": 1, "HP": 100}})]).run()
	assert_true(r.is_win())
	assert_eq(r.winner_team, "A")
	assert_almost(r.end_time, 8.0, 1e-9, "5 (lanzamiento) + 3")


func test_delayed_validation_and_limit() -> void:
	var reg := OperationRegistry.new()
	var nested := {"id": "x", "effects": [{"type": "delayed_effect", "delay": 1, "effects": [{"type": "delayed_effect", "delay": 1, "effects": [{"type": "heal", "formula": "1"}]}]}]}
	assert_contains(" ".join(AbilityDef.from_dict(nested, reg)["errors"]), "anidado")
	assert_true(AbilityDef.from_dict({"id": "x", "effects": [{"type": "delayed_effect", "delay": 0, "effects": [{"type": "heal", "formula": "1"}]}]}, reg)["ability"] == null)
	assert_true(AbilityDef.from_dict({"id": "x", "effects": [{"type": "delayed_effect", "delay": 1, "effects": [{"type": "magia"}]}]}, reg)["ability"] == null)
	var bomb := {"id": "bomb", "targeting": "enemy", "effects": [{"type": "delayed_effect", "delay": 50, "effects": [{"type": "heal", "formula": "1"}]}]}
	var a := _tem([bomb], {"stats": {"SPD": 200}, "ai": {"type": "priority_list", "rules": [{"ability": "bomb"}]}})
	var eng := engine([a, _dummy()], 1, {"safety": {"max_scheduled": 2}, "victory": {"limits": {"max_turns": 12}}})
	var r := eng.run()
	assert_false(r.is_aborted())
	assert_eq(events(eng, EventTypes.DELAYED_SCHEDULED).size(), 2)
	assert_true(events(eng, EventTypes.LIMIT_REACHED).any(func(e): return e["data"].get("limit", "") == "max_scheduled"))


func test_repeat_action_is_free_and_needs_a_previous_action() -> void:
	var strike := dmg_ability("strike", "10", {"cost": {"mana": 10}, "cooldown": 5})
	var echo := {"id": "echo", "targeting": "enemy", "effects": [{"type": "repeat_action", "times": 2}]}
	var a := _tem([strike, echo])
	var t := _dummy()
	var eng := engine([a, t])
	eng.start()
	_cast(eng, a, "echo", t)
	assert_almost(t.hp, 9000.0, 1e-9, "sin accion previa no hace nada")
	_cast(eng, a, "strike", t)
	assert_almost(t.hp, 8990.0)
	_cast(eng, a, "echo", t)
	assert_almost(t.hp, 8970.0, 1e-9, "repite 2 veces la accion anterior (strike)")
	assert_almost((a.get_resource("mana") as ResourceState).value, 40.0, 1e-9, "las repeticiones no pagan coste")
	assert_true(events(eng, EventTypes.ACTION_STARTED).any(func(e): return e["data"].get("via", "") == "repeat"))


func test_copy_action_uses_targets_last_ability() -> void:
	var sting := dmg_ability("sting", "33", {"cost": {"venom": 99}})
	var copy := {"id": "mimic", "targeting": "enemy", "effects": [{"type": "copy_action"}]}
	var a := _tem([copy])
	var t := ent("t", "B", {"abilities": [sting], "resources": {"venom": {"initial": 99, "max": 99}}, "stats": {"SPD": 1, "HP": 9000, "ACC": 1.0}})
	var eng := engine([a, t])
	eng.start()
	_cast(eng, a, "mimic", t)
	assert_almost(t.hp, 9000.0, 1e-9, "el objetivo aun no uso nada")
	t.last_action = {"ability": "sting", "targets": ["a"]}
	_cast(eng, a, "mimic", t)
	assert_almost(t.hp, 9000.0 - 33.0, 1e-9, "usa la habilidad ajena (y su coste en venom no se exige)")
	assert_true(a.get_ability("sting") == null)


# --- escenarios combinados, limites y trazabilidad --------------------------------------------------------------

func _complex_team() -> Array:
	var mage := ent("mage", "A", {
		"stats": {"SPD": 130, "HP": 900, "MAG": 150, "ACC": 1.0}, "resources": {"mana": {"initial": 100, "max": 100, "regen_per_turn": 5}},
		"statuses": [{"id": "ward", "duration": 3, "beneficial": true, "defense": {"absorb": {"amount": "120"}, "reflect": {"pct": 0.25}}},
			{"id": "venom", "duration": 3, "stacking": {"policy": "stack_intensity", "max_stacks": 3}, "periodic": [{"on": "turn_end", "effects": [
				{"type": "damage", "always_hit": true, "can_crit": false, "components": [{"damage_type": "true", "formula": "12 * status.stacks"}]}]}]}],
		"abilities": [
			{"id": "shield_up", "targeting": "self", "cooldown": 4, "effects": [{"type": "apply_status", "status": "ward"}]},
			{"id": "sting", "targeting": "enemy", "cost": {"mana": 10}, "effects": [{"type": "damage", "components": [{"damage_type": "magical", "formula": "caster.MAG"}]},
				{"type": "apply_status", "status": "venom", "chance": 0.6}]},
			{"id": "pet", "targeting": "self", "uses_per_combat": 1, "effects": [{"type": "summon", "template": "imp", "lifespan": 3}]},
			{"id": "riposte", "targeting": "enemy", "action_type": "reaction", "trigger": {"event": "damage_dealt", "when": {"event.target": {"eq": "self"}, "event.source": {"eq": "enemy"}}, "chance": 0.5, "target": "event_source"},
				"effects": [{"type": "damage", "components": [{"damage_type": "physical", "formula": "30"}]}], "cooldown": 2}],
		"summons": {"imp": {"stats": {"HP": 120, "ATK": 40, "SPD": 150, "ACC": 1.0}, "basic_attack": true}},
		"ai": {"type": "priority_list", "rules": [{"ability": "pet", "target": "self"}, {"ability": "shield_up", "target": "self"}, {"ability": "sting", "target": "lowest_hp_enemy"}]}})
	var knight := ent("knight", "B", {
		"stats": {"SPD": 100, "HP": 1500, "ATK": 120, "DEF": 150, "ACC": 1.0}, "basic_attack": true,
		"abilities": [{"id": "stagger", "targeting": "enemy", "cooldown": 3, "effects": [{"type": "apply_status", "status": "stun", "chance": 0.4}, {"type": "modify_initiative", "mode": "add", "amount": "-200"}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "stagger", "target": "first_enemy"}, {"ability": "basic_attack", "target": "lowest_hp_enemy"}]}})
	return [mage, knight]


func test_combined_scenario_is_deterministic_and_causally_consistent() -> void:
	var hashes: Array = []
	var summary: Array = []
	for rep in 2:
		var eng := engine(_complex_team(), 21, {"victory": {"limits": {"max_turns": 60}}})
		var r := eng.run()
		assert_false(r.is_aborted(), str(r.error))
		check_causality(eng)
		hashes.append(r.log_hash)
		summary.append([r.outcome, r.winner_team, r.turns, r.events])
	assert_eq(hashes[0], hashes[1], "misma semilla = misma huella")
	assert_eq(summary[0], summary[1])


func test_combined_scenario_exercises_the_whole_pipeline() -> void:
	var eng := engine(_complex_team(), 21, {"victory": {"limits": {"max_turns": 60}}})
	eng.run()
	var seen := {}
	for ev in eng.log.events:
		seen[ev["type"]] = true
	for must in [EventTypes.STATUS_APPLIED, EventTypes.STATUS_GAINED, EventTypes.PROC, EventTypes.SUMMON_CREATED, EventTypes.EVENT_MODIFIED,
			EventTypes.DAMAGE_DEALT, EventTypes.RESOURCE_CHANGED, EventTypes.TURN_ENDED]:
		assert_true(seen.has(must), "aparece %s" % must)


func test_trace_levels_equivalent_with_phase3_content() -> void:
	var full := engine(_complex_team(), 5, {"victory": {"limits": {"max_turns": 40}}})
	var rf := full.run()
	var red := CombatEngine.new()
	red.setup(Ruleset.from_dict({"victory": {"limits": {"max_turns": 40, "stagnation_turns": 99}}}), _complex_team(), 5, EventLog.TraceLevel.REDUCED)
	var rr := red.run()
	assert_eq(rf.log_hash, rr.log_hash)
	assert_eq(rf.to_dict(), rr.to_dict())


func test_many_seeds_never_abort_or_leave_inconsistent_state() -> void:
	for seed_value in range(1, 16):
		var eng := engine(_complex_team(), seed_value, {"victory": {"limits": {"max_turns": 80}}})
		var r := eng.run()
		assert_false(r.is_aborted(), "semilla %d: %s" % [seed_value, str(r.error)])
		for e in eng.entities:
			assert_true(e.hp >= 0.0 and e.hp <= e.hp_max() + 1e-9, "vida acotada")
			if not e.alive:
				assert_eq(e.statuses.size(), 0, "los muertos no conservan estados")
			for rid in e.resources:
				var res: ResourceState = e.resources[rid]
				assert_true(res.value >= res.min_value and res.value <= res.max_value, "recursos acotados")
		for ev in eng.log.of_type(EventTypes.DAMAGE_DEALT):
			assert_true(float(ev["data"]["applied"]) >= 0.0 and float(ev["data"]["overkill"]) >= 0.0)


func test_runaway_content_is_stopped_by_technical_limits() -> void:
	# Contenido hostil: reaccion que se auto-dispara + invocacion en cadena + efectos retrasados.
	var spam := {"id": "spam", "targeting": "self", "action_type": "reaction", "effects": [
		{"type": "summon", "template": "x"}, {"type": "delayed_effect", "delay": 1, "effects": [{"type": "heal", "formula": "1"}]}],
		"trigger": {"event": "summon_created"}}
	var a := ent("a", "A", {"stats": {"SPD": 100}, "abilities": [spam, {"id": "go", "targeting": "self", "effects": [{"type": "summon", "template": "x"}]}],
		"summons": {"x": {"stats": {"HP": 10, "SPD": 50}}}, "ai": {"type": "priority_list", "rules": [{"ability": "go", "target": "self"}]}})
	var eng := engine([a, _dummy()], 1, {"safety": {"max_reaction_chain": 3, "max_scheduled": 20}, "summons": {"max_per_owner": 6, "max_entities": 12}, "victory": {"limits": {"max_turns": 20}}})
	var r := eng.run()
	assert_false(r.is_aborted(), "los limites cortan sin abortar: %s" % str(r.error))
	assert_true(eng.entities.size() <= 12)
	assert_true(r.events < 5000)


# --- eventos de usuario, metricas, cooldowns y patrones de categorias -----------------------------------------------

func test_user_events_metrics_and_triggered_chain() -> void:
	var build := {"id": "charge", "targeting": "self", "effects": [
		{"type": "emit_event", "name": "combo_ready", "data": {"n": 3, "kind": "fire"}},
		{"type": "metric", "name": "charges_built", "amount": 2}]}
	var finisher := dmg_ability("finisher", "40", {"action_type": "reaction", "trigger": {"event": "user.combo_ready", "when": {"event.n": {"ge": 3}, "event.kind": {"eq": "fire"}}, "target": "lowest_hp_enemy"}})
	var a := ent("a", "A", {"stats": {"SPD": 200, "ACC": 1.0}, "abilities": [build, finisher], "ai": {"type": "priority_list", "rules": [{"ability": "charge", "target": "self"}]}})
	var eng := engine([a, _dummy()], 1, {"victory": {"limits": {"max_turns": 3}}})
	var r := eng.run()
	assert_true(events(eng, "user.combo_ready").size() >= 1)
	assert_true(events(eng, EventTypes.DAMAGE_DEALT).size() >= 1, "el evento de usuario dispara la reaccion")
	assert_true(float(r.metrics["charges_built"]["total"]) >= 2.0)
	assert_eq(r.metrics["charges_built"]["by_entity"].keys(), ["a"])
	var reg := OperationRegistry.new()
	assert_true(AbilityDef.from_dict({"id": "x", "effects": [{"type": "emit_event", "name": "Mal Nombre"}]}, reg)["ability"] == null)
	assert_true(AbilityDef.from_dict({"id": "x", "effects": [{"type": "emit_event", "name": "ok", "data": {"o": {}}}]}, reg)["ability"] == null)
	assert_true(AbilityDef.from_dict({"id": "x", "effects": [{"type": "metric", "name": "m", "amount": "9 +"}]}, reg)["ability"] == null)


func test_modify_cooldown_reduce_add_reset() -> void:
	var nuke := dmg_ability("nuke", "1", {"cooldown": 4})
	var cdr := {"id": "cdr", "targeting": "self", "effects": [{"type": "modify_cooldown", "ability": "nuke", "mode": "reduce", "amount": 3}]}
	var slow := {"id": "slow", "targeting": "self", "effects": [{"type": "modify_cooldown", "mode": "add", "amount": 2}]}
	var rst := {"id": "rst", "targeting": "self", "effects": [{"type": "modify_cooldown", "mode": "reset"}]}
	var a := ent("a", "A", {"abilities": [nuke, cdr, slow, rst]})
	var t := _dummy()
	var eng := engine([a, t])
	eng.start()
	_cast(eng, a, "nuke", t)
	assert_almost((a.cooldowns["nuke"] as Duration).remaining, 4.0)
	_cast(eng, a, "cdr", a)
	assert_almost((a.cooldowns["nuke"] as Duration).remaining, 1.0)
	_cast(eng, a, "slow", a)
	assert_almost((a.cooldowns["nuke"] as Duration).remaining, 3.0)
	_cast(eng, a, "rst", a)
	assert_false(a.cooldowns.has("nuke"))


func test_toggle_and_sustained_patterns_are_composable() -> void:
	# Alternable: dos habilidades con `requires` sobre el estado; sostenida: coste periodico por turno
	# y se apaga solo al agotarse el recurso (disparador sobre resource_limit).
	var stance := {"id": "aura", "tags": ["buff"], "beneficial": true, "duration": {"unit": "permanent"}, "modifiers": [{"stat": "DEF", "kind": "flat", "value": 60}],
		"periodic": [{"on": "turn_start", "effects": [{"type": "modify_resource", "resource": "focus", "amount": "-4"}]}]}
	var on := {"id": "aura_on", "targeting": "self", "requires": {"self.status.aura": {"eq": 0}}, "effects": [{"type": "apply_status", "status": "aura"}]}
	var off := {"id": "aura_off", "targeting": "self", "requires": {"self.status.aura": {"ge": 1}}, "effects": [{"type": "remove_status", "status": "aura"}]}
	var drained := {"id": "aura_drained", "targeting": "self", "action_type": "reaction", "effects": [{"type": "remove_status", "status": "aura", "force": true}],
		"trigger": {"event": "resource_limit", "when": {"event.resource": {"eq": "focus"}, "event.limit": {"eq": "min"}, "event.target": {"eq": "self"}}, "target": "self"}}
	var a := ent("a", "A", {"stats": {"SPD": 100}, "statuses": [stance], "abilities": [on, off, drained], "resources": {"focus": {"initial": 10, "max": 10}}})
	var eng := engine([a, _dummy()], 1, {"victory": {"limits": {"max_turns": 12}}})
	eng.start()
	var t := TurnState.new(a, 1)
	var legal := func() -> Array: return ViewBuilder.build(eng, a, t)["legal_actions"].map(func(x): return x["ability_id"])
	assert_eq(legal.call(), ["aura_on"], "alternable: solo 'on' si no esta activa")
	_cast(eng, a, "aura_on", a)
	assert_eq(legal.call(), ["aura_off"], "y solo 'off' cuando esta activa")
	assert_almost(a.stats.get_value("DEF"), 160.0)
	eng.run()
	assert_eq(a.status_stacks("aura"), 0, "sostenida: se apaga al agotar el recurso")
	assert_almost((a.get_resource("focus") as ResourceState).value, 0.0)
	assert_true(events(eng, EventTypes.REACTION_TRIGGERED).any(func(e): return e["data"]["ability"] == "aura_drained"))


func test_channel_variants_charged_ability_with_resource() -> void:
	# "Cargada": cast_time + coste al comprometer; se interrumpe sin devolver el coste (D-016).
	var charged := dmg_ability("overcharge", "500", {"cast_time": 8, "cost": {"mana": 30}})
	var a := ent("a", "A", {"stats": {"SPD": 100, "ACC": 1.0}, "abilities": [charged], "resources": {"mana": {"initial": 50, "max": 50}},
		"ai": {"type": "priority_list", "rules": [{"ability": "overcharge"}]}})
	var eng := engine([a, _dummy()], 1, {"victory": {"limits": {"max_virtual_time": 30, "stagnation_turns": 99}}})
	eng.scheduler.schedule(14 * S, func(e: CombatEngine): e.status_service.apply("stun", e.get_entity("a"), e.get_entity("t")), "stun_a")
	eng.run()
	assert_eq(events(eng, EventTypes.CHANNEL_INTERRUPTED).size(), 1)
	assert_almost((a.get_resource("mana") as ResourceState).value, 20.0, 1e-9, "el coste ya se pago al comprometer; no se devuelve")
