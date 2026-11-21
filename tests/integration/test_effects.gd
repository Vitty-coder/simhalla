extends TestCase
## Operaciones de efecto sobre el motor: modificacion/cancelacion de dano, multigolpe, elementos.


func _caster(extra: Dictionary) -> CombatEntity:
	var data := {"id": "c", "team": "A", "basic_attack": false, "stats": {"SPD": 300, "ACC": 1.0, "CRIT": 0.0}}
	data.merge(extra, true)
	var b := EntityFactory.build(data, BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())
	assert_true(b["errors"].is_empty(), str(b["errors"]))
	return b["entity"]


func _hit_once(ability: Dictionary, target_stats: Dictionary = {}, rules: Dictionary = {}) -> CombatEngine:
	var c := _caster({"abilities": [ability], "ai": {"type": "priority_list", "rules": [{"ability": ability["id"]}]}})
	var t := make_entity("t", "B", merged(target_stats, {"SPD": 1.0, "EVA": 0.0}), false)
	var r := {"victory": {"limits": {"max_turns": 1}}}
	r.merge(rules, true)
	var eng := make_engine([c, t], 5, r)
	eng.run()
	return eng


func merged(a: Dictionary, b: Dictionary) -> Dictionary:
	var out := b.duplicate()
	out.merge(a, true)
	return out


func test_multicomponent_mixed_types_and_elements() -> void:
	var ab := {"id": "combo", "effects": [{"type": "damage", "components": [
		{"damage_type": "physical", "formula": "200"},
		{"damage_type": "magical", "element": "fire", "formula": "200"},
		{"damage_type": "true", "formula": "50"}]}]}
	var eng := _hit_once(ab, {"DEF": 100.0, "RES": 300.0, "ELEM_RES.fire": 0.5, "HP": 5000.0})
	var amounts := eng.log.of_type(EventTypes.DAMAGE_DEALT).map(func(e): return e["data"]["amount"])
	# fisico 100; magico 200*100/400=50 * 0.5 (fuego) = 25; verdadero 50
	assert_eq(amounts, [100.0, 25.0, 50.0])
	assert_almost(eng.get_entity("t").hp, 5000.0 - 175.0)


func test_damage_pre_interceptor_can_reduce_like_a_shield() -> void:
	var ab := {"id": "hit", "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "100"}]}]}
	var c := _caster({"abilities": [ab], "ai": {"type": "priority_list", "rules": [{"ability": "hit"}]}})
	var t := make_entity("t", "B", {"SPD": 1.0, "EVA": 0.0}, false)
	var eng := make_engine([c, t], 5, {"victory": {"limits": {"max_turns": 1}}})
	eng.dispatcher.intercept(EventTypes.DAMAGE_PRE, func(ev: CombatEvent, _g): ev.set_data("amount", ev.data["amount"] - 30.0, "escudo"), 0, "escudo")
	eng.run()
	assert_almost(t.hp, 930.0, 1e-9, "100 - 30 absorbidos")
	var mod := eng.log.of_type(EventTypes.EVENT_MODIFIED)
	assert_eq(mod.size(), 1)
	var dealt := eng.log.of_type(EventTypes.DAMAGE_DEALT)[0]
	assert_almost(dealt["data"]["amount"], 70.0)
	assert_almost(dealt["data"]["intended"], 100.0, 1e-9, "dano intentado se conserva separado del efectivo")


func test_damage_pre_cancel_prevents_damage() -> void:
	var ab := {"id": "hit", "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "100"}]}]}
	var c := _caster({"abilities": [ab], "ai": {"type": "priority_list", "rules": [{"ability": "hit"}]}})
	var t := make_entity("t", "B", {"SPD": 1.0, "EVA": 0.0}, false)
	var eng := make_engine([c, t], 5, {"victory": {"limits": {"max_turns": 1}}})
	eng.dispatcher.intercept(EventTypes.DAMAGE_PRE, func(ev: CombatEvent, _g): ev.cancel("inmunidad"), 0, "inm")
	eng.run()
	assert_almost(t.hp, 1000.0)
	assert_eq(eng.log.of_type(EventTypes.DAMAGE_DEALT).size(), 0)
	assert_eq(eng.log.of_type(EventTypes.EVENT_CANCELLED).size(), 1)


func test_multihit_revalidates_dead_target() -> void:
	var ab := {"id": "flurry", "effects": [{"type": "damage", "components": [
		{"damage_type": "true", "formula": "500"}, {"damage_type": "true", "formula": "500"}, {"damage_type": "true", "formula": "500"}]}]}
	var eng := _hit_once(ab, {"HP": 800.0})
	assert_eq(eng.log.of_type(EventTypes.DAMAGE_DEALT).size(), 2, "el tercer golpe no se aplica a un objetivo muerto")
	assert_eq(eng.log.of_type(EventTypes.DEATH).size(), 1)
	assert_false(eng.get_entity("t").alive)
	assert_almost(eng.get_entity("t").hp, 0.0)
	var dealt := eng.log.of_type(EventTypes.DAMAGE_DEALT)
	assert_almost(dealt[1]["data"]["overkill"], 200.0, 1e-9, "sobreexceso registrado aparte")
	assert_almost(dealt[1]["data"]["applied"], 300.0)


func test_missing_attack_deals_no_damage_but_action_resolves() -> void:
	var ab := {"id": "hit", "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "100"}]}]}
	var eng := _hit_once(ab, {"EVA": 5.0}) # imposible acertar (suelo 0)
	assert_eq(eng.log.of_type(EventTypes.MISS).size(), 1)
	assert_eq(eng.log.of_type(EventTypes.DAMAGE_DEALT).size(), 0)
	assert_eq(eng.log.of_type(EventTypes.ACTION_RESOLVED).size(), 1)


func test_always_hit_ignores_evasion_but_still_crit_roll() -> void:
	var ab := {"id": "hit", "effects": [{"type": "damage", "always_hit": true, "components": [{"damage_type": "true", "formula": "100"}]}]}
	var eng := _hit_once(ab, {"EVA": 5.0})
	assert_eq(eng.log.of_type(EventTypes.HIT).size(), 1)
	assert_eq(eng.log.of_type(EventTypes.MISS).size(), 0)
	assert_almost(eng.get_entity("t").hp, 900.0)


func test_crit_only_when_authorized() -> void:
	var stats := {"id": "c", "team": "A", "basic_attack": false, "stats": {"SPD": 300, "ACC": 1.0, "CRIT": 1.0}}
	for can_crit in [true, false]:
		var ab := {"id": "hit", "effects": [{"type": "damage", "can_crit": can_crit, "components": [{"damage_type": "true", "formula": "100"}]}]}
		var d := stats.duplicate(true)
		d["abilities"] = [ab]
		d["ai"] = {"type": "priority_list", "rules": [{"ability": "hit"}]}
		var b := EntityFactory.build(d, BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())
		var t := make_entity("t", "B", {"SPD": 1.0, "EVA": 0.0}, false)
		var eng := make_engine([b["entity"], t], 5, {"victory": {"limits": {"max_turns": 1}}})
		eng.run()
		assert_almost(t.hp, 850.0 if can_crit else 900.0, 1e-9, "can_crit=%s" % str(can_crit))


func test_formula_reads_caster_and_target_state() -> void:
	# Dano segun vida perdida del objetivo y del lanzador.
	var ab := {"id": "execute", "effects": [{"type": "damage", "components": [
		{"damage_type": "true", "formula": "target.hp_missing * 0.5 + caster.hp_ratio * 10 + caster.res.rage"}]}]}
	var c := _caster({"resources": {"rage": {"initial": 7, "max": 100}}, "abilities": [ab], "ai": {"type": "priority_list", "rules": [{"ability": "execute"}]}})
	var t := make_entity("t", "B", {"SPD": 1.0, "EVA": 0.0, "HP": 1000.0}, false)
	var eng := make_engine([c, t], 5, {"victory": {"limits": {"max_turns": 1}}}, EventLog.TraceLevel.FULL, {"t": {"hp": 600.0}})
	eng.run()
	# 400*0.5 + 1*10 + 7 = 217
	assert_almost(t.hp, 600.0 - 217.0, 1e-9)


func test_targeting_self_and_ally() -> void:
	var ab := {"id": "ward", "targeting": "ally", "effects": [{"type": "heal", "formula": "100"}]}
	var c := _caster({"abilities": [ab], "ai": {"type": "priority_list", "rules": [{"ability": "ward", "target": "lowest_hp_ally"}]}})
	var ally := make_entity("friend", "A", {"SPD": 1.0}, false)
	var foe := make_entity("foe", "B", {"SPD": 1.0}, false)
	var eng := make_engine([c, ally, foe], 5, {"victory": {"limits": {"max_turns": 1}}}, EventLog.TraceLevel.FULL, {"friend": {"hp": 500.0}})
	eng.run()
	assert_almost(ally.hp, 600.0)
	assert_eq(eng.log.of_type(EventTypes.HEAL_DONE)[0]["target"], "friend")
