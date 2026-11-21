extends Phase3Case
## Cierre de la fase 3: catalogo elemental, selectores deterministas, artefacto completo,
## invertir/propagar estados, suspender efectos y cooldowns, restaurar estados y "reservar".

func _dummy(id: String = "t", team: String = "B", extra: Dictionary = {}) -> CombatEntity:
	var d := {"stats": {"SPD": 1, "HP": 9000, "EVA": 0.0}}
	d.merge(extra, true)
	return ent(id, team, d)


func _cast(eng: CombatEngine, caster: CombatEntity, ability: String, target: CombatEntity) -> void:
	ActionResolver.resolve(eng, TurnState.new(caster, 1), caster, caster.get_ability(ability), [target] as Array[CombatEntity], 0)


func _status(id: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "duration": 3}
	d.merge(extra, true)
	return d


# --- catalogo elemental -------------------------------------------------------------------------------

func test_elements_catalog_validated_everywhere() -> void:
	var rs := Ruleset.from_dict({})
	var cases := {
		"habilidad": {"abilities": [dmg_ability("x", "1", {"effects": [{"type": "damage", "components": [{"damage_type": "true", "element": "plasma", "formula": "1"}]}]})]},
		"estadistica": {"stats": {"ELEM_RES.plasma": 0.5}},
		"afinidad": {"stats": {"ELEM_AFF.plasma": 0.5}},
		"pasiva": {"abilities": [{"id": "p", "passive": {"modifiers": [{"stat": "ELEM_RES.plasma", "kind": "flat", "value": 0.1}]}}]},
		"estado": {"statuses": [{"id": "s", "defense": {"immune_elements": ["plasma"]}}]},
		"estado_mod": {"statuses": [{"id": "s", "modifiers": [{"stat": "ELEM_AFF.plasma", "kind": "flat", "value": 0.1}]}]},
		"invocacion": {"summons": {"w": {"stats": {"ELEM_RES.plasma": 0.1}}}},
	}
	for k in cases:
		var eng := CombatEngine.new()
		var errs := eng.setup(rs, [ent("a", "A", cases[k]), _dummy()], 1)
		assert_true(errs.size() > 0, "debe rechazar: %s" % k)
		assert_contains(" ".join(errs), "plasma")
		assert_contains(" ".join(errs), "catalogo")
	# elementos validos y catalogo ampliado por el reglamento
	var ok := ent("a", "A", {"stats": {"ELEM_RES.fire": 0.2}, "abilities": [dmg_ability("f", "1", {"effects": [{"type": "damage", "components": [{"damage_type": "true", "element": "fire", "formula": "1"}]}]})]})
	assert_eq(CombatEngine.new().setup(rs, [ok, _dummy()], 1), [])
	var wide := Ruleset.from_dict({"elements": ["plasma"]})
	assert_eq(CombatEngine.new().setup(wide, [ent("a", "A", {"stats": {"ELEM_RES.plasma": 0.5}}), _dummy()], 1), [])
	assert_true(CombatEngine.new().setup(wide, [ent("a", "A", {"stats": {"ELEM_RES.fire": 0.5}}), _dummy()], 1).size() > 0, "el catalogo del reglamento manda")


func test_elements_ruleset_validation() -> void:
	for bad in [{"elements": "fuego"}, {"elements": ["Fuego"]}, {"elements": ["a", "a"]}, {"elements": [5]}]:
		assert_false(Ruleset.from_dict(bad).is_valid(), JSON.stringify(bad))
	assert_true(Ruleset.from_dict({"elements": []}).is_valid(), "catalogo vacio = sin elementos")


func test_summon_with_unknown_element_aborts_cleanly_not_silently() -> void:
	var ab := {"id": "call", "targeting": "self", "effects": [{"type": "summon", "template": "w"}]}
	var s := ent("s", "A", {"stats": {"SPD": 200}, "abilities": [ab], "ai": {"type": "priority_list", "rules": [{"ability": "call", "target": "self"}]},
		"summons": {"w": {"stats": {"ELEM_RES.plasma": 0.1}}}})
	var eng := CombatEngine.new()
	assert_contains(" ".join(eng.setup(Ruleset.from_dict({}), [s, _dummy()], 1)), "plasma")


# --- selectores -----------------------------------------------------------------------------------------

func _multi(on: String, seed_value: int = 1) -> CombatEngine:
	var ab := {"id": "nova", "targeting": "self", "effects": [{"type": "damage", "on": on, "always_hit": true, "can_crit": false, "components": [{"damage_type": "true", "formula": "100"}]}]}
	var a := ent("a", "A", {"abilities": [ab]})
	var ally := _dummy("ally", "A")
	var e1 := _dummy("e1", "B")
	var e2 := _dummy("e2", "B")
	e2.stats.set_base("HP", 500.0)
	var eng := engine([a, ally, e1, e2], seed_value)
	eng.start()
	e2.hp = 500.0
	_cast(eng, a, "nova", a)
	return eng


func test_target_selectors() -> void:
	var all_e := _multi("all_enemies")
	assert_almost(all_e.get_entity("e1").hp, 8900.0)
	assert_almost(all_e.get_entity("e2").hp, 400.0)
	assert_almost(all_e.get_entity("a").hp, 1000.0)
	assert_almost(all_e.get_entity("ally").hp, 9000.0)
	var all_a := _multi("all_allies")
	assert_almost(all_a.get_entity("ally").hp, 8900.0)
	assert_almost(all_a.get_entity("a").hp, 1000.0, 1e-9, "all_allies no incluye al lanzador")
	var low := _multi("lowest_hp_enemy")
	assert_almost(low.get_entity("e2").hp, 400.0)
	assert_almost(low.get_entity("e1").hp, 9000.0)
	var caster := _multi("caster")
	assert_almost(caster.get_entity("a").hp, 900.0)


func test_random_selector_is_deterministic_and_uses_its_own_stream() -> void:
	var picks: Array = []
	for rep in 2:
		var seq: Array = []
		for s in range(1, 9):
			var eng := _multi("random_enemy", s)
			seq.append("e1" if eng.get_entity("e1").hp < 9000.0 else "e2")
		picks.append(seq)
	assert_eq(picks[0], picks[1], "misma semilla, mismas elecciones")
	assert_true(picks[0].has("e1") and picks[0].has("e2"), "distintas semillas eligen distinto: %s" % str(picks[0]))
	var eng := _multi("random_ally", 3)
	assert_almost(eng.get_entity("ally").hp, 8900.0)


func test_trigger_random_enemy_and_on_validation() -> void:
	var tr := dmg_ability("zap", "10", {"action_type": "reaction", "trigger": {"event": "user.ping", "target": "random_enemy"}})
	var emit := {"id": "ping", "targeting": "self", "effects": [{"type": "emit_event", "name": "ping"}]}
	var a := ent("a", "A", {"abilities": [tr, emit]})
	var e1 := _dummy("e1")
	var e2 := _dummy("e2")
	var eng := engine([a, e1, e2], 5)
	eng.start()
	_cast(eng, a, "ping", a)
	assert_eq(events(eng, EventTypes.REACTION_TRIGGERED).size(), 1)
	assert_true(e1.hp < 9000.0 or e2.hp < 9000.0)
	var reg := OperationRegistry.new()
	assert_true(AbilityDef.from_dict({"id": "x", "effects": [{"type": "heal", "formula": "1", "on": "todos"}]}, reg)["ability"] == null)


# --- artefacto con todas las herramientas -------------------------------------------------------------------

func _artifact_entity(art: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var d := {"id": "a", "team": "A", "basic_attack": true, "stats": {"SPD": 200, "ACC": 1.0}, "artifact": art}
	d.merge(extra, true)
	return EntityFactory.build(d, BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())


func test_artifact_full_toolset() -> void:
	var art := {"id": "relic", "modifiers": [{"stat": "ATK", "kind": "flat", "value": 40}],
		"resources": {"charge": {"initial": 2, "max": 3, "regen_per_turn": 1}},
		"statuses": [{"id": "relic_mark", "duration": 2, "modifiers": [{"stat": "DEF", "kind": "flat", "value": -30}]}],
		"summons": {"spark": {"stats": {"HP": 30, "SPD": 100}, "basic_attack": true}},
		"abilities": [
			{"id": "zap", "targeting": "enemy", "cost": {"charge": 2}, "effects": [{"type": "apply_status", "status": "relic_mark"}, {"type": "summon", "template": "spark", "lifespan": 2}]},
			{"id": "relic_aura", "passive": {"modifiers": [{"stat": "RES", "kind": "flat", "value": 25}]}}],
		"ai_rules": [{"ability": "zap", "target": "first_enemy"}]}
	var b := _artifact_entity(art)
	assert_true(b["errors"].is_empty(), str(b["errors"]))
	var e: CombatEntity = b["entity"]
	assert_true(e.resources.has("charge"))
	assert_eq(e.custom_statuses.size(), 1)
	assert_true(e.summon_templates.has("spark"))
	var eng := engine([e, _dummy()], 1, {"victory": {"limits": {"max_turns": 8, "stagnation_turns": 99}}})
	assert_almost(e.stats.get_value("RES"), 125.0, 1e-9, "pasiva del artefacto")
	eng.run()
	var used: Array = events(eng, EventTypes.ACTION_RESOLVED).filter(func(x): return x["source"] == "a").map(func(x): return x["data"]["ability"])
	assert_eq(used[0], "zap", "las reglas de IA del artefacto tienen prioridad")
	assert_true(events(eng, EventTypes.STATUS_APPLIED).size() >= 1 and events(eng, EventTypes.SUMMON_CREATED).size() >= 1)
	assert_true(used.has("basic_attack"), "el resto de la IA sigue funcionando cuando zap no es legal (sin carga)")


func test_artifact_conflicts_and_errors() -> void:
	var conflict := _artifact_entity({"id": "r", "resources": {"mana": {"initial": 1}}}, {"resources": {"mana": {"initial": 5}}})
	assert_contains(" ".join(conflict["errors"]), "ya existe")
	var dup_tmpl := _artifact_entity({"id": "r", "summons": {"w": {}}}, {"summons": {"w": {}}})
	assert_contains(" ".join(dup_tmpl["errors"]), "ya existe")
	var diff_status := _artifact_entity({"id": "r", "statuses": [{"id": "s", "duration": 5}]}, {"statuses": [{"id": "s", "duration": 2}]})
	assert_contains(" ".join(diff_status["errors"]), "otro contenido")
	var same_status := _artifact_entity({"id": "r", "statuses": [{"id": "s", "duration": 2}]}, {"statuses": [{"id": "s", "duration": 2}]})
	assert_true(same_status["errors"].is_empty(), "definicion identica admitida")
	var passive_ai := _artifact_entity({"id": "r", "ai_rules": [{"ability": "basic_attack"}]}, {"ai": {"type": "passive"}})
	assert_contains(" ".join(passive_ai["errors"]), "priority_list")
	var ghost := _artifact_entity({"id": "r", "ai_rules": [{"ability": "nada"}]})
	assert_contains(" ".join(ghost["errors"]), "inexistente")
	var bad_tmpl := _artifact_entity({"id": "r", "summons": {"w": {"stats": {"HP": 0}}}})
	assert_contains(" ".join(bad_tmpl["errors"]), "artifact.summons.w")
	var bad_key := _artifact_entity({"id": "r", "script": "x"})
	assert_contains(" ".join(bad_key["errors"]), "propiedad desconocida 'script'")


# --- invertir ----------------------------------------------------------------------------------------------------

func test_invert_modifiers_and_toggle() -> void:
	var defs := [_status("rage", {"beneficial": true, "modifiers": [{"stat": "ATK", "kind": "flat", "value": 50}, {"stat": "SPD", "kind": "mult", "value": 2.0}, {"stat": "DEF", "kind": "pct_add", "value": 0.5}]})]
	var inv := {"id": "flip", "targeting": "enemy", "effects": [{"type": "invert_status", "status": "rage"}]}
	var a := ent("a", "A", {"abilities": [inv], "statuses": defs})
	var t := _dummy()
	var eng := engine([a, t])
	eng.start()
	eng.status_service.apply("rage", t, t)
	assert_almost(t.stats.get_value("ATK"), 150.0)
	assert_almost(t.stats.get_value("SPD"), 2.0)
	_cast(eng, a, "flip", t)
	assert_almost(t.stats.get_value("ATK"), 50.0, 1e-9, "buff -> debuff")
	assert_almost(t.stats.get_value("SPD"), 0.5, 1e-9, "mult invertido")
	assert_almost(t.stats.get_value("DEF"), 50.0, 1e-9, "pct_add negado")
	assert_true(t.statuses[0].inverted)
	assert_eq(events(eng, EventTypes.STATUS_CHANGED).filter(func(e): return e["data"]["change"] == "inverted").size(), 1)
	_cast(eng, a, "flip", t)
	assert_almost(t.stats.get_value("ATK"), 150.0, 1e-9, "invertir otra vez lo deshace")


func test_invert_periodic_damage_to_heal_and_beneficial_filter() -> void:
	var poison := _status("tox", {"duration": 4, "periodic": [{"on": "turn_end", "effects": [{"type": "damage", "always_hit": true, "can_crit": false, "components": [{"damage_type": "true", "formula": "20"}, {"damage_type": "true", "formula": "5"}]}]}]})
	var a := ent("a", "A", {"statuses": [poison]})
	var t := _dummy("t", "B", {"stats": {"SPD": 100, "HP": 1000}})
	var eng := engine([a, t], 1, {"victory": {"limits": {"max_turns": 4, "stagnation_turns": 99}}})
	eng.start()
	eng.status_service.apply("tox", t, a)
	t.hp = 500.0
	eng.status_service.invert(t.statuses[0])
	assert_eq(eng.status_service.matching(t, {"beneficial": true}).size(), 1, "tras invertir cuenta como beneficioso")
	eng.run()
	assert_true(t.hp > 500.0, "el veneno invertido cura: %s" % str(t.hp))
	assert_true(events(eng, EventTypes.HEAL_DONE).size() >= 1)
	assert_almost(events(eng, EventTypes.HEAL_DONE)[0]["data"]["amount"], 25.0, 1e-9, "suma de componentes")


func test_invert_effect_function_pairs() -> void:
	var h := StatusService.invert_effect({"type": "heal", "formula": "7", "chance": 0.5})
	assert_eq(h["type"], "damage")
	assert_eq(h["chance"], 0.5)
	assert_eq(StatusService.invert_effect({"type": "apply_status", "status": "x"})["type"], "apply_status", "lo demas no cambia")


# --- propagar ---------------------------------------------------------------------------------------------------------

func _team(extra: Dictionary = {}) -> Array:
	var a := ent("a", "A", {"abilities": [{"id": "spread", "targeting": "enemy", "effects": [{"type": "propagate_status", "status": "plague", "to": "target_allies"}]},
		{"id": "spread_c", "targeting": "enemy", "effects": [{"type": "propagate_status", "tags": ["disease"], "to": "caster_enemies", "count": 1}]},
		{"id": "spread_r", "targeting": "enemy", "effects": [{"type": "propagate_status", "status": "plague", "to": "random_other"}]}],
		"statuses": [_status("plague", {"tags": ["disease"], "duration": 5, "stacking": {"policy": "stack_intensity", "max_stacks": 3}})]})
	var t1 := _dummy("t1")
	var t2 := _dummy("t2")
	var t3 := _dummy("t3")
	return [a, t1, t2, t3]


func test_propagate_to_target_allies_preserves_state() -> void:
	var ents := _team()
	var eng := engine(ents)
	eng.start()
	var a: CombatEntity = ents[0]
	var t1: CombatEntity = ents[1]
	eng.status_service.apply("plague", t1, a, {"stacks": 2, "magnitude": 3.0})
	t1.statuses[0].duration.remaining = 2.0
	_cast(eng, a, "spread", t1)
	for o in [ents[2], ents[3]]:
		assert_eq(o.status_stacks("plague"), 2, "%s recibe la copia" % o.id)
		assert_almost(o.statuses[0].duration.remaining, 2.0, 1e-9, "duracion restante conservada")
		assert_almost(o.statuses[0].magnitude, 3.0)
		assert_eq(o.statuses[0].source_id, "a", "origen original")
	assert_eq(a.statuses.size(), 0, "no al lanzador (es enemigo del objetivo)")
	assert_eq(t1.status_stacks("plague"), 2, "el original sigue")


func test_propagate_count_and_caster_relative_and_random() -> void:
	var ents := _team()
	var eng := engine(ents, 4)
	eng.start()
	var a: CombatEntity = ents[0]
	eng.status_service.apply("plague", ents[1], a)
	_cast(eng, a, "spread_c", ents[1])
	assert_eq(ents[2].status_stacks("plague") + ents[3].status_stacks("plague"), 1, "count=1 limita (caster_enemies excluye la fuente)")
	var eng2 := engine(_team(), 4)
	eng2.start()
	var e2 := eng2.entities
	eng2.status_service.apply("plague", e2[1], e2[0])
	_cast(eng2, e2[0], "spread_r", e2[1])
	var got := e2.filter(func(x): return x.id != "t1" and x.status_stacks("plague") > 0)
	assert_eq(got.size(), 1, "random_other: un receptor")
	var eng3 := engine(_team(), 4)
	eng3.start()
	eng3.status_service.apply("plague", eng3.entities[1], eng3.entities[0])
	_cast(eng3, eng3.entities[0], "spread_r", eng3.entities[1])
	var got3 := eng3.entities.filter(func(x): return x.id != "t1" and x.status_stacks("plague") > 0)
	assert_eq(got.map(func(x): return x.id), got3.map(func(x): return x.id), "reproducible")


func test_propagate_on_expire_and_on_death() -> void:
	var contagion := _status("contagion", {"duration": 1, "tags": ["disease"], "on_expire": [{"type": "propagate_status", "status": "contagion", "to": "target_allies", "count": 1}],
		"on_death": [{"type": "propagate_status", "status": "contagion", "to": "target_allies"}]})
	# on_death: al morir el portador, se extiende a sus aliados
	var a := ent("a", "A", {"statuses": [contagion]})
	var t1 := _dummy("t1", "B", {"stats": {"SPD": 1, "HP": 100}})
	var t2 := _dummy("t2")
	var eng := engine([a, t1, t2])
	eng.start()
	eng.status_service.apply("contagion", t1, a)
	hit(eng, a, t1, 9999.0)
	assert_false(t1.alive)
	assert_eq(t2.status_stacks("contagion"), 1, "se propaga al morir")
	# on_expire
	var a2 := ent("a", "A", {"statuses": [contagion]})
	var u1 := _dummy("u1")
	var u2 := _dummy("u2")
	var eng2 := engine([a2, u1, u2])
	eng2.start()
	eng2.status_service.apply("contagion", u1, a2)
	eng2.status_service.remove(u1.statuses[0], "expired")
	assert_eq(u2.status_stacks("contagion"), 1, "se propaga al expirar")
	assert_true(u1.statuses.is_empty())


# --- suspender efectos y cooldowns ---------------------------------------------------------------------------------

func test_suspend_statuses_by_tag() -> void:
	var buff := _status("might", {"tags": ["buff"], "duration": 3, "modifiers": [{"stat": "ATK", "kind": "flat", "value": 60}],
		"periodic": [{"on": "turn_end", "effects": [{"type": "heal", "formula": "10"}]}], "defense": {"absorb": {"amount": "100"}}})
	var curse := _status("curse2", {"tags": ["debuff"], "duration": 3, "modifiers": [{"stat": "DEF", "kind": "flat", "value": -20}]})
	var stasis := _status("stasis", {"duration": 2, "flags": {"suspend_statuses": ["buff"]}})
	var a := ent("a", "A", {"statuses": [buff, curse, stasis]})
	var t := _dummy("t", "B", {"stats": {"SPD": 100, "HP": 5000}})
	var eng := engine([a, t])
	eng.start()
	eng.status_service.apply("might", t, a)
	eng.status_service.apply("curse2", t, a)
	assert_almost(t.stats.get_value("ATK"), 160.0)
	var shield_before: float = t.statuses[0].shield
	eng.status_service.apply("stasis", t, a)
	assert_almost(t.stats.get_value("ATK"), 100.0, 1e-9, "el buff queda suspendido")
	assert_almost(t.stats.get_value("DEF"), 80.0, 1e-9, "el debuff sigue activo")
	assert_true(t.statuses.filter(func(s): return s.def.id == "might")[0].frozen)
	assert_false(t.statuses.filter(func(s): return s.def.id == "curse2")[0].frozen)
	# defensa suspendida: el escudo no absorbe
	t.hp = 1000.0
	hit(eng, a, t, 50.0)
	assert_almost(t.hp, 950.0, 1e-9, "escudo suspendido")
	assert_almost(t.statuses.filter(func(s): return s.def.id == "might")[0].shield, shield_before)
	# reanudacion
	eng.status_service.dispel(t, {"status": "stasis"}, "test", 0)
	assert_almost(t.stats.get_value("ATK"), 160.0, 1e-9, "se reanuda")
	assert_false(t.statuses.filter(func(s): return s.def.id == "might")[0].frozen)
	assert_true(events(eng, EventTypes.STATUS_CHANGED).any(func(e): return e["data"]["change"] == "suspended"))
	assert_true(events(eng, EventTypes.STATUS_CHANGED).any(func(e): return e["data"]["change"] == "resumed"))


func test_suspended_statuses_do_not_tick_or_fire_periodics() -> void:
	var burn := _status("slow_burn", {"tags": ["dot"], "duration": 2, "periodic": [{"on": "turn_end", "effects": [{"type": "damage", "always_hit": true, "can_crit": false, "components": [{"damage_type": "true", "formula": "10"}]}]}]})
	var stasis := _status("stasis", {"duration": 2, "flags": {"suspend_statuses": ["*"]}})
	var a := ent("a", "A", {"statuses": [burn, stasis]})
	var t := _dummy("t", "B", {"stats": {"SPD": 100, "HP": 5000}})
	var eng := engine([a, t], 1, {"victory": {"limits": {"max_turns": 9, "stagnation_turns": 99}}})
	eng.start()
	eng.status_service.apply("slow_burn", t, a)
	eng.status_service.apply("stasis", t, a)
	assert_false(t.statuses.filter(func(s): return s.def.id == "stasis")[0].frozen, "'*' no se suspende a si mismo")
	eng.run()
	var ticks := events(eng, EventTypes.DAMAGE_DEALT).filter(func(e): return e["target"] == "t").size()
	assert_eq(ticks, 2, "el dot solo actua tras acabar la estasis (2 ticks, 2 turnos)")
	var exp := events(eng, EventTypes.STATUS_EXPIRED).map(func(e): return e["data"]["status"])
	assert_eq(exp, ["stasis", "slow_burn"], "primero la estasis; despues el dot, que no cuenta atras mientras esta suspendido")


func test_suspended_time_duration_is_paused_and_rearmed() -> void:
	var timed := _status("aura_t", {"tags": ["buff"], "duration": {"unit": "time", "amount": 10}})
	var stasis := _status("stasis", {"duration": {"unit": "time", "amount": 4}, "flags": {"suspend_statuses": ["buff"]}})
	var a := ent("a", "A", {"statuses": [timed, stasis]})
	var t := _dummy()
	var eng := engine([a, t], 1, {"victory": {"limits": {"max_virtual_time": 60, "stagnation_turns": 99}}})
	eng.scheduler.schedule(2 * S, func(e: CombatEngine): e.status_service.apply("stasis", e.get_entity("t"), e.get_entity("a")), "freeze")
	eng.start()
	eng.status_service.apply("aura_t", t, a)
	eng.run()
	var exp := events(eng, EventTypes.STATUS_EXPIRED)
	var times := {}
	for e in exp:
		times[e["data"]["status"]] = e["time"]
	assert_eq(times["stasis"], 6 * S, "estasis de 4 u.t. desde t=2")
	assert_eq(times["aura_t"], 14 * S, "10 u.t. de duracion + 4 u.t. pausado = t=14")


func test_suspend_cooldowns() -> void:
	var nuke := dmg_ability("nuke", "1", {"cooldown": 2})
	var freeze_cd := _status("chrono", {"duration": 1, "flags": {"suspend_cooldowns": true}})
	var a := ent("a", "A", {"abilities": [nuke], "statuses": [freeze_cd], "stats": {"SPD": 100}})
	var t := _dummy()
	var eng := engine([a, t], 1, {"victory": {"limits": {"max_turns": 2, "stagnation_turns": 99}}})
	eng.start()
	_cast(eng, a, "nuke", t)
	eng.status_service.apply("chrono", a, a)
	var du: Duration = a.cooldowns["nuke"]
	eng.emit(EventTypes.TURN_STARTED, "a", "", {"turn": 1})
	assert_almost(du.remaining, 2.0, 1e-9, "no avanza mientras esta suspendido")
	eng.status_service.dispel(a, {"status": "chrono"}, "test", 0)
	eng.emit(EventTypes.TURN_STARTED, "a", "", {"turn": 2})
	assert_almost(du.remaining, 1.0, 1e-9, "reanuda")


func test_suspend_flag_validation() -> void:
	var reg := OperationRegistry.new()
	assert_true(StatusDef.from_dict({"id": "x", "flags": {"suspend_statuses": []}}, reg)["def"] == null)
	assert_true(StatusDef.from_dict({"id": "x", "flags": {"suspend_cooldowns": "si"}}, reg)["def"] == null)
	assert_true(StatusDef.from_dict({"id": "x", "flags": {"suspend_statuses": ["buff"], "suspend_cooldowns": true}}, reg)["def"] != null)


# --- restaurar estados --------------------------------------------------------------------------------------------------------

func test_record_and_restore_statuses() -> void:
	var rec := {"id": "rec", "targeting": "self", "effects": [{"type": "record_state", "key": "k", "what": ["statuses", "hp"]}]}
	var rst := {"id": "rst", "targeting": "self", "effects": [{"type": "restore_state", "key": "k", "what": ["statuses"]}]}
	var defs := [_status("alpha", {"duration": 5, "modifiers": [{"stat": "ATK", "kind": "flat", "value": 10}], "stacking": {"policy": "stack_intensity", "max_stacks": 3}}),
		_status("beta", {"duration": 4}), _status("gamma", {"duration": 3, "dispellable": false})]
	var a := ent("a", "A", {"abilities": [rec, rst], "statuses": defs})
	var eng := engine([a, _dummy()])
	eng.start()
	eng.status_service.apply("alpha", a, a, {"stacks": 2})
	eng.status_service.apply("beta", a, a)
	a.statuses[0].duration.remaining = 3.0
	eng.status_service.invert(a.statuses[0])
	_cast(eng, a, "rec", a)
	# cambia todo: quita beta, anade gamma (no disipable), cambia pilas/duracion
	eng.status_service.dispel(a, {"status": "beta"}, "t", 0)
	eng.status_service.apply("gamma", a, a)
	eng.status_service.apply("alpha", a, a)
	_cast(eng, a, "rst", a)
	var ids := a.statuses.map(func(s): return s.def.id)
	ids.sort()
	assert_eq(ids, ["alpha", "beta"], "conjunto restaurado (gamma, aunque no disipable, se retira)")
	var alpha := a.statuses.filter(func(s): return s.def.id == "alpha")[0] as StatusInstance
	assert_eq(alpha.stacks, 2)
	assert_almost(alpha.duration.remaining, 3.0, 1e-9, "duracion restante grabada")
	assert_true(alpha.inverted)
	assert_almost(a.stats.get_value("ATK"), 100.0 - 20.0, 1e-9, "modificadores coherentes con lo restaurado (invertido x2 pilas)")
	assert_true(a.stored_states.is_empty(), "no duplicable")


# --- reservar (patron: preparar y liberar) -------------------------------------------------------------------------------------------

func test_reserve_pattern_prepare_then_release_once() -> void:
	var brace := {"id": "brace", "targeting": "self", "effects": [{"type": "apply_status", "status": "braced"}]}
	var riposte := {"id": "riposte", "targeting": "enemy", "action_type": "reaction", "requires": {"self.status.braced": {"ge": 1}},
		"trigger": {"event": "damage_dealt", "when": {"event.target": {"eq": "self"}}, "target": "event_source"},
		"effects": [{"type": "damage", "always_hit": true, "can_crit": false, "components": [{"damage_type": "true", "formula": "50"}]}, {"type": "remove_status", "status": "braced", "on": "caster"}]}
	var a := ent("a", "A", {"abilities": [brace, riposte], "statuses": [{"id": "braced", "duration": {"unit": "permanent"}, "beneficial": true}]})
	var t := _dummy()
	var eng := engine([a, t])
	eng.start()
	hit(eng, t, a, 10.0)
	assert_eq(events(eng, EventTypes.REACTION_TRIGGERED).size(), 0, "sin preparar, no reacciona")
	_cast(eng, a, "brace", a)
	hit(eng, t, a, 10.0)
	assert_eq(events(eng, EventTypes.REACTION_TRIGGERED).size(), 1, "reaccion reservada, se libera")
	assert_almost(t.hp, 8950.0)
	hit(eng, t, a, 10.0)
	assert_eq(events(eng, EventTypes.REACTION_TRIGGERED).size(), 1, "la reserva se consumio")


# --- paquetes con las novedades ------------------------------------------------------------------------------------------------------------

func test_package_with_closure_features_imports() -> void:
	var tmp := "user://_tests_closure/pkg"
	var files := {
		"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": "t/closer", "version": "1.0.0", "type": "character", "name": "C"}),
		"character.json": JSON.stringify({"schema": "simhalla.character/1", "name": "C"}),
		"abilities.json": JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "spread", "targeting": "enemy", "effects": [
			{"type": "propagate_status", "status": "pest", "to": "target_allies"}, {"type": "invert_status", "status": "pest", "on": "random_enemy"}]}]}),
		"effects.json": JSON.stringify({"schema": "simhalla.effects/1", "statuses": [{"id": "pest", "tags": ["disease"], "duration": 3,
			"flags": {"suspend_cooldowns": true}, "on_death": [{"type": "propagate_status", "status": "pest", "to": "target_allies"}]}]}),
		"artifact.json": JSON.stringify({"schema": "simhalla.artifact/1", "id": "rod", "resources": {"ink": {"initial": 5, "max": 5}}, "ai_rules": [{"ability": "spread", "target": "first_enemy"}]}),
	}
	for rel in files:
		DirAccess.make_dir_recursive_absolute(tmp)
		var f := FileAccess.open(tmp.path_join(rel), FileAccess.WRITE)
		f.store_string(files[rel])
		f.close()
	var lib := ContentLibrary.new("user://_tests_closure/lib")
	var rep := PackageImporter.new(lib).import_package(tmp)
	assert_true(rep.ok(), "\n".join(rep.errors))
	# elemento fuera del catalogo: el ensayo en motor real lo rechaza
	var bad := files.duplicate()
	bad["abilities.json"] = JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "spread", "targeting": "enemy", "effects": [{"type": "damage", "components": [{"damage_type": "true", "element": "plasma", "formula": "1"}]}]}]})
	var tmp2 := "user://_tests_closure/pkg2"
	for rel in bad:
		DirAccess.make_dir_recursive_absolute(tmp2)
		var f2 := FileAccess.open(tmp2.path_join(rel), FileAccess.WRITE)
		f2.store_string(bad[rel])
		f2.close()
	var rep2 := PackageImporter.new(ContentLibrary.new("user://_tests_closure/lib2")).validate(tmp2)
	assert_false(rep2.ok())
	assert_contains("\n".join(rep2.errors), "plasma")
	ContentLibrary._remove_tree("user://_tests_closure")
