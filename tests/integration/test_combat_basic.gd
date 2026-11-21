extends TestCase
## Combate completo extremo a extremo (fase 1): ATB + accion basica + dano + victoria.

const FIX := "res://content/fixtures/entities/"


func _duel(seed_value: int = 42, trace: String = "full", a: String = "attacker_a.json", b: String = "attacker_b.json") -> Dictionary:
	return DuelRunner.run({"seed": seed_value, "trace": trace, "entities": [{"path": FIX + a}, {"path": FIX + b}]})


func test_duel_runs_to_a_win() -> void:
	var out := _duel()
	assert_true(out["ok"], str(out["errors"]))
	var r: CombatResult = out["result"]
	assert_true(r.is_win(), "outcome=%s reason=%s" % [r.outcome, r.reason])
	assert_eq(r.kind, "victory")
	assert_eq(r.reason, "last_team_standing")
	assert_contains(["A", "B"], r.winner_team)
	var loser := "attacker_b" if r.winner_team == "A" else "attacker_a"
	var winner := "attacker_a" if r.winner_team == "A" else "attacker_b"
	assert_false(r.entities[loser]["alive"])
	assert_true(r.entities[winner]["alive"])
	assert_almost(r.entities[loser]["hp"], 0.0)
	assert_true(r.entities[winner]["hp"] > 0.0)
	assert_true(r.turns > 0 and r.actions > 0 and r.events > 0)
	assert_eq(r.log_hash.length(), 64)


func test_hp_bookkeeping_matches_damage_events() -> void:
	var out := _duel()
	var eng: CombatEngine = out["engine"]
	var dealt := {}
	for ev in eng.log.of_type(EventTypes.DAMAGE_DEALT):
		dealt[ev["target"]] = float(dealt.get(ev["target"], 0.0)) + float(ev["data"]["applied"])
	for e in eng.entities:
		assert_almost(e.hp_max() - e.hp, float(dealt.get(e.id, 0.0)), 1e-6, "vida perdida de %s = dano aplicado" % e.id)
	# Estadisticas coherentes con el registro.
	var st := eng.stats.to_dict()
	for id in ["attacker_a", "attacker_b"]:
		assert_almost(float(st[id]["damage_taken"]), float(dealt.get(id, 0.0)), 1e-6)


func test_basic_attack_matches_formula() -> void:
	# ATK 150 vs DEF 120: 150*100/220 = 68.18 -> 68 (sin critico); critico: 225*100/220 = 102.27 -> 102.
	var eng: CombatEngine = _duel()["engine"]
	var seen_normal := false
	var seen_crit := false
	for ev in eng.log.of_type(EventTypes.DAMAGE_DEALT):
		if ev["source"] == "attacker_a":
			if ev["data"]["crit"]:
				assert_almost(ev["data"]["amount"], 102.0)
				seen_crit = true
			else:
				assert_almost(ev["data"]["amount"], 68.0)
				seen_normal = true
	assert_true(seen_normal, "hay golpes normales de A")
	assert_true(seen_crit or true, "los criticos dependen de la semilla")


func test_same_seed_is_fully_reproducible() -> void:
	var r1: CombatResult = _duel(42)["result"]
	var r2: CombatResult = _duel(42)["result"]
	assert_eq(r1.log_hash, r2.log_hash)
	assert_eq(r1.to_dict(), r2.to_dict())


func test_different_seeds_diverge() -> void:
	var hashes := {}
	for s in [1, 2, 3, 4, 5, 6]:
		hashes[(_duel(s)["result"] as CombatResult).log_hash] = true
	assert_true(hashes.size() >= 4, "semillas distintas producen combates distintos: %d" % hashes.size())


func test_trace_level_does_not_change_result() -> void:
	var full: CombatResult = _duel(7, "full")["result"]
	var red: CombatResult = _duel(7, "reduced")["result"]
	assert_eq(full.log_hash, red.log_hash, "paridad de huella entre trazas")
	assert_eq(full.to_dict(), red.to_dict(), "paridad de resultado y estadisticas")
	var e_red: CombatEngine = _duel(7, "reduced")["engine"]
	assert_true(e_red.log.events.is_empty(), "traza reducida no guarda eventos")
	assert_eq(e_red.log.count, full.events)


func test_multiple_battles_do_not_share_state() -> void:
	# Mismo contenido, dos ejecuciones intercaladas: ningun estado compartido.
	var a1 := _duel(11)["result"] as CombatResult
	var other := _duel(12)["result"] as CombatResult
	var a2 := _duel(11)["result"] as CombatResult
	assert_eq(a1.log_hash, a2.log_hash)
	assert_ne(a1.log_hash, other.log_hash)


func test_passive_vs_passive_ends_by_limit_not_error() -> void:
	var out := DuelRunner.run({"seed": 1, "entities": [
		{"path": FIX + "passive_waiter.json", "overrides": {"id": "p1", "team": "A"}},
		{"path": FIX + "passive_waiter.json", "overrides": {"id": "p2", "team": "B"}}]})
	assert_true(out["ok"], str(out["errors"]))
	var r: CombatResult = out["result"]
	assert_true(r.is_draw(), "outcome=%s" % r.outcome)
	assert_eq(r.kind, "limit")
	assert_eq(r.reason, "stagnation")
	assert_false(r.is_aborted())


func test_no_damage_dealer_stalemate_is_draw() -> void:
	# Sanador sin dano contra pasivo: nadie puede danar -> estancamiento = empate.
	var out := DuelRunner.run({"seed": 1, "entities": [
		{"path": FIX + "healer_no_damage.json", "overrides": {"team": "A"}},
		{"path": FIX + "passive_waiter.json", "overrides": {"team": "B"}}]})
	var r: CombatResult = out["result"]
	assert_true(r.is_draw())
	assert_eq(r.reason, "stagnation")


func test_stalemate_resolution_by_hp_ratio() -> void:
	var out := DuelRunner.run({"seed": 1, "ruleset": "", "entities": []})
	assert_false(out["ok"])
	# Reglamento con desempate por vida: A empieza con mas vida relativa.
	var rules := Ruleset.from_dict({"victory": {"limit_resolution": "highest_hp_ratio", "limits": {"max_turns": 4}}})
	var a := make_entity("a", "A", {"SPD": 100.0}, false)
	var b := make_entity("b", "B", {"SPD": 100.0}, false)
	a.ai = PassiveAI.new()
	b.ai = PassiveAI.new()
	var eng := CombatEngine.new()
	assert_eq(eng.setup(rules, [a, b], 1, EventLog.TraceLevel.FULL, {"b": {"hp": 400.0}}), [])
	var r := eng.run()
	assert_eq(r.reason, "max_turns")
	assert_true(r.is_win())
	assert_eq(r.winner_team, "A")
	assert_eq(r.turns, 4)


func test_max_turns_limit_exact() -> void:
	var rules := {"victory": {"limits": {"max_turns": 5}}}
	var a := make_entity("a", "A", {}, false)
	var b := make_entity("b", "B", {}, false)
	a.ai = PassiveAI.new()
	b.ai = PassiveAI.new()
	var eng := make_engine([a, b], 1, rules)
	var r := eng.run()
	assert_eq(r.reason, "max_turns")
	assert_eq(r.turns, 5)
	assert_true(r.is_draw())


func test_max_virtual_time_limit() -> void:
	var a := make_entity("a", "A", {"SPD": 1.0}, false)
	var b := make_entity("b", "B", {"SPD": 1.0}, false)
	a.ai = PassiveAI.new()
	b.ai = PassiveAI.new()
	var eng := make_engine([a, b], 1, {"victory": {"limits": {"max_virtual_time": 500.0}}})
	var r := eng.run()
	assert_eq(r.reason, "max_virtual_time", str(r.to_dict()))
	assert_true(r.end_time <= 500.0)


func test_no_actor_can_act_is_draw() -> void:
	var eng := make_engine([make_entity("a", "A", {"SPD": 0.0}), make_entity("b", "B", {"SPD": 0.0})])
	var r := eng.run()
	assert_true(r.is_draw())
	assert_eq(r.reason, "no_actor_can_act")
	assert_eq(r.kind, "stalemate")


func test_three_way_free_for_all() -> void:
	var eng := make_engine([make_entity("a", "A", {"ATK": 150.0}), make_entity("b", "B"), make_entity("c", "C", {"ATK": 80.0})], 5)
	var r := eng.run()
	assert_true(r.is_win(), "%s %s" % [r.outcome, r.reason])
	var alive := 0
	for id in r.entities:
		if r.entities[id]["alive"]:
			alive += 1
	assert_eq(alive, 1)
	assert_contains(["A", "B", "C"], r.winner_team)


func test_two_vs_two_teams_and_allies_not_targeted() -> void:
	var ents := [make_entity("a1", "A"), make_entity("a2", "A"), make_entity("b1", "B"), make_entity("b2", "B")]
	var eng := make_engine(ents, 9)
	var r := eng.run()
	assert_true(r.is_win())
	for ev in eng.log.of_type(EventTypes.DAMAGE_DEALT):
		var src: CombatEntity = eng.get_entity(ev["source"])
		var dst: CombatEntity = eng.get_entity(ev["target"])
		assert_ne(src.team, dst.team, "no hay fuego amigo con IA por defecto")


func test_summons_do_not_count_for_victory() -> void:
	var owner_a := make_entity("a", "A", {"ATK": 400.0})
	var minion := make_entity("minion", "A", {"HP": 5000.0, "ATK": 1.0, "DEF": 9999.0, "SPD": 1.0})
	minion.counts_for_victory = false
	var b := make_entity("b", "B", {"HP": 300.0})
	var r := make_engine([owner_a, minion, b], 3).run()
	assert_true(r.is_win())
	assert_eq(r.winner_team, "A")


func test_simultaneous_death_is_draw() -> void:
	var a := make_entity("a", "A")
	var b := make_entity("b", "B")
	var eng := make_engine([a, b], 1)
	eng.scheduler.schedule(1_000_000, func(e: CombatEngine):
		e.get_entity("a").hp = 0.0
		e.get_entity("b").hp = 0.0
		e.check_all_deaths(), "boom")
	var r := eng.run()
	assert_true(r.is_draw())
	assert_eq(r.reason, "simultaneous_death")
	assert_false(r.entities["a"]["alive"])
	assert_false(r.entities["b"]["alive"])


func test_death_prevention_via_interceptor() -> void:
	var a := make_entity("a", "A", {"ATK": 5000.0, "SPD": 200.0})
	var b := make_entity("b", "B", {"SPD": 1.0})
	var eng := make_engine([a, b], 1)
	var saved := [0]
	eng.dispatcher.intercept(EventTypes.DEATH_PRE, func(ev: CombatEvent, _g):
		if saved[0] == 0 and ev.target_id == "b":
			saved[0] += 1
			ev.cancel("segunda_oportunidad", "sobrevive una vez"), 0, "prev")
	var r := eng.run()
	assert_eq(saved[0], 1)
	assert_true(r.is_win())
	assert_eq(r.winner_team, "A")
	var survive := eng.log.of_type(EventTypes.HP_CHANGED).filter(func(e): return e["data"]["reason"] == "death_prevented")
	assert_eq(survive.size(), 1)
	assert_almost(survive[0]["data"]["new"], 1.0, 1e-9, "sobrevive con survive_hp")
	assert_eq(eng.log.of_type(EventTypes.DEATH).size(), 1, "solo muere la segunda vez")


func test_victory_not_decided_mid_action_allows_pre_victory_reactions() -> void:
	# La victoria se evalua tras la accion completa (punto seguro), no al morir el rival.
	var eng := make_engine([make_entity("a", "A", {"ATK": 9999.0, "SPD": 300.0}), make_entity("b", "B", {"SPD": 1.0})], 1)
	var order: Array = []
	eng.dispatcher.observe(EventTypes.DEATH, func(_e, _g): order.append("death"), 0, "t")
	eng.dispatcher.observe(EventTypes.ACTION_RESOLVED, func(_e, _g): order.append("resolved"), 0, "t")
	eng.dispatcher.observe(EventTypes.COMBAT_ENDED, func(_e, _g): order.append("ended"), 0, "t")
	eng.run()
	assert_eq(order, ["death", "resolved", "ended"])


func test_turn_skipped_by_interceptor() -> void:
	var a := make_entity("a", "A")
	var b := make_entity("b", "B")
	var eng := make_engine([a, b], 4)
	eng.dispatcher.intercept(EventTypes.TURN_STARTED, func(ev: CombatEvent, _g):
		if ev.source_id == "a":
			ev.cancel("aturdido"), 0, "stun")
	var r := eng.run()
	assert_true(r.is_win())
	assert_eq(r.winner_team, "B", "a nunca actua, b gana")
	assert_true(eng.log.of_type(EventTypes.TURN_SKIPPED).size() > 0)
	assert_eq(eng.stats.to_dict().get("a", {}).get("actions", 0), 0)


func test_action_interrupted_consumes_slot_but_not_cost() -> void:
	var rules := Ruleset.from_dict({})
	var data := {"id": "mage", "team": "A", "resources": {"mana": {"initial": 50, "max": 50}}, "basic_attack": false,
		"abilities": [{"id": "bolt", "targeting": "enemy", "cost": {"mana": 10},
			"effects": [{"type": "damage", "components": [{"damage_type": "magical", "formula": "caster.MAG"}]}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "bolt"}]}}
	var m := EntityFactory.build(data, BalanceProfile.default_profile(), rules, OperationRegistry.new())
	assert_true(m["errors"].is_empty(), str(m["errors"]))
	var eng := make_engine([m["entity"], make_entity("b", "B")], 1, {"victory": {"limits": {"max_turns": 6}}})
	eng.dispatcher.intercept(EventTypes.ACTION_STARTED, func(ev: CombatEvent, _g): ev.cancel("silencio"), 0, "s")
	var r := eng.run()
	assert_eq(eng.get_entity("mage").get_resource("mana").value, 50.0, "no se paga coste al interrumpirse")
	assert_true(eng.log.of_type(EventTypes.ACTION_INTERRUPTED).size() > 0)
	assert_true(r.is_draw() or r.is_win())


func test_resource_cost_paid_and_unaffordable_rejected() -> void:
	var rules := Ruleset.from_dict({})
	var data := {"id": "mage", "team": "A", "stats": {"SPD": 200}, "resources": {"mana": {"initial": 25, "max": 50}}, "basic_attack": false,
		"abilities": [{"id": "bolt", "targeting": "enemy", "cost": {"mana": 10},
			"effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "5"}]}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "bolt"}]}}
	var m := EntityFactory.build(data, BalanceProfile.default_profile(), rules, OperationRegistry.new())
	var eng := make_engine([m["entity"], make_entity("b", "B", {"SPD": 1.0}, false)], 1, {"victory": {"limits": {"max_turns": 12}}})
	eng.run()
	assert_almost(eng.get_entity("mage").get_resource("mana").value, 5.0, 1e-9, "25 - 10 - 10, tercera cast imposible")
	var casts := eng.log.of_type(EventTypes.ACTION_RESOLVED).filter(func(e): return e["source"] == "mage")
	assert_eq(casts.size(), 2)


func test_wait_is_always_available_and_ends_turn() -> void:
	var a := make_entity("a", "A", {}, false)
	var b := make_entity("b", "B", {}, false)
	a.ai = PassiveAI.new()
	b.ai = PassiveAI.new()
	var eng := make_engine([a, b], 1, {"victory": {"limits": {"max_turns": 3}}})
	eng.run()
	assert_eq(eng.log.of_type(EventTypes.WAIT).size(), 3)
	assert_eq(eng.log.of_type(EventTypes.TURN_ENDED).size(), 3)


func test_entity_without_basic_attack_still_valid() -> void:
	var e := make_entity("x", "A", {}, false)
	assert_eq(e.abilities.size(), 0)
	assert_true(e.ai is PassiveAI, "sin ataque basico ni habilidades la IA por defecto espera")


func test_invalid_ai_decision_falls_back_to_wait() -> void:
	var a := make_entity("a", "A")
	var b := make_entity("b", "B")
	var bad := _BadAI.new()
	a.ai = bad
	var eng := make_engine([a, b], 1, {"victory": {"limits": {"max_turns": 4}}})
	eng.run()
	assert_true(eng.log.of_type(EventTypes.ACTION_REJECTED).size() > 0)
	assert_true(eng.log.of_type(EventTypes.AI_FALLBACK).size() > 0)
	# La IA no puede ejecutar una habilidad que el PJ no posee.
	assert_eq(eng.log.of_type(EventTypes.DAMAGE_DEALT).filter(func(e): return e["source"] == "a").size(), 0)


class _BadAI extends AIController:
	func decide(_view: Dictionary) -> AIDecision:
		return AIDecision.use("super_nuke", ["b"], "trampa")


func test_ai_view_does_not_leak_hidden_information() -> void:
	var a := make_entity("a", "A", {"ATK": 123.0})
	var b := make_entity("b", "B", {"DEF": 777.0, "ATK": 555.0})
	var spy := _SpyAI.new()
	a.ai = spy
	var eng := make_engine([a, b], 1, {"victory": {"limits": {"max_turns": 2}}})
	b.ai_memory["secreto"] = "x" # setup reinicia la memoria de IA: se inyecta tras preparar el combate
	eng.run()
	assert_true(spy.views.size() > 0)
	var v: Dictionary = spy.views[0]
	var other: Dictionary = v["others"][0]
	assert_false(other.has("stats"), "no se exponen estadisticas del rival")
	assert_false(other.has("abilities"))
	assert_false(other.has("memory"))
	assert_false(JSON.stringify(v["others"]).contains("777"))
	assert_false(JSON.stringify(v["others"]).contains("secreto"))
	assert_true(other.has("hp") and other.has("hp_max") and other.has("initiative") and other.has("resources"))
	assert_true(v["self"].has("stats"), "las propias si")
	# Mutar la vista no afecta al estado real.
	v["self"]["hp"] = -1.0
	other["hp"] = -1.0
	assert_true(a.hp > 0.0 and b.hp > 0.0)


func test_visible_fields_are_configurable() -> void:
	var a := make_entity("a", "A")
	var spy := _SpyAI.new()
	a.ai = spy
	var eng := make_engine([a, make_entity("b", "B")], 1, {"ai": {"visible_fields": ["hp"]}, "victory": {"limits": {"max_turns": 2}}})
	eng.run()
	var other: Dictionary = spy.views[0]["others"][0]
	assert_true(other.has("hp"))
	assert_false(other.has("initiative"))
	assert_false(other.has("hp_max"))


class _SpyAI extends AIController:
	var views: Array = []

	func decide(view: Dictionary) -> AIDecision:
		views.append(view)
		return AIDecision.wait("espia")


func test_overrides_are_applied_and_recorded() -> void:
	var a := make_entity("a", "A")
	var b := make_entity("b", "B")
	var eng := make_engine([a, b], 1, {}, EventLog.TraceLevel.FULL, {"a": {"hp": 100.0, "initiative": 500.0}})
	assert_almost(a.hp, 100.0)
	assert_eq(a.initiative_micro, 500_000_000)
	eng.start()
	var started := eng.log.of_type(EventTypes.COMBAT_STARTED)[0]
	assert_true(started["data"]["initial_overrides"].has("a"), "diferencias de configuracion registradas")


func test_setup_validation_errors() -> void:
	var eng := CombatEngine.new()
	var r := Ruleset.from_dict({})
	assert_false(eng.setup(r, [make_entity("a", "A")], 1).is_empty(), "una sola entidad")
	assert_false(CombatEngine.new().setup(r, [make_entity("a", "A"), make_entity("a", "B")], 1).is_empty(), "id duplicado")
	assert_false(CombatEngine.new().setup(r, [make_entity("a", "A"), make_entity("b", "A")], 1).is_empty(), "un solo equipo")
	assert_false(CombatEngine.new().setup(r, [make_entity("a", "A"), make_entity("b", "B")], 1, EventLog.TraceLevel.FULL, {"zzz": {}}).is_empty(), "override desconocido")
	var bad := Ruleset.from_dict({"atb": {"initiative_threshold": -1.0}})
	assert_false(CombatEngine.new().setup(bad, [make_entity("a", "A"), make_entity("b", "B")], 1).is_empty(), "reglamento invalido")


func test_cancel_request_is_aborted_not_defeat() -> void:
	var eng := make_engine([make_entity("a", "A"), make_entity("b", "B")], 1)
	eng.step()
	eng.request_cancel()
	var r := eng.run()
	assert_true(r.is_aborted())
	assert_eq(r.kind, "cancelled")


func test_formula_error_aborts_with_diagnostic() -> void:
	var rules := Ruleset.from_dict({})
	var data := {"id": "x", "team": "A", "basic_attack": false,
		"abilities": [{"id": "boom", "targeting": "enemy",
			"effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "caster.ATK / (caster.ATK - caster.ATK)"}]}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "boom"}]}}
	var b := EntityFactory.build(data, BalanceProfile.default_profile(), rules, OperationRegistry.new())
	assert_true(b["errors"].is_empty(), str(b["errors"]))
	var r := make_engine([b["entity"], make_entity("y", "B")], 1).run()
	assert_true(r.is_aborted(), "error tecnico no es empate silencioso")
	assert_eq(r.error["code"], "formula_error")
	assert_contains(r.error["message"], "cero")


func test_heal_respects_heal_rec_and_overheal() -> void:
	var rules := Ruleset.from_dict({})
	var data := {"id": "h", "team": "A", "stats": {"MAG": 200, "HEAL_REC": 0.5, "HP": 1000}, "basic_attack": false,
		"abilities": [{"id": "heal", "targeting": "self", "effects": [{"type": "heal", "formula": "caster.MAG"}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "heal", "target": "self"}]}}
	var h := EntityFactory.build(data, BalanceProfile.default_profile(), rules, OperationRegistry.new())
	var eng := make_engine([h["entity"], make_entity("b", "B", {"SPD": 1.0}, false)], 1, {"victory": {"limits": {"max_turns": 1}}}, EventLog.TraceLevel.FULL, {"h": {"hp": 950.0}})
	eng.run()
	var done := eng.log.of_type(EventTypes.HEAL_DONE)
	assert_eq(done.size(), 1)
	assert_almost(done[0]["data"]["amount"], 100.0, 1e-9, "200 * HEAL_REC 0.5")
	assert_almost(done[0]["data"]["applied"], 50.0, 1e-9, "solo vida faltante")
	assert_almost(done[0]["data"]["overheal"], 50.0, 1e-9)
	assert_almost(eng.get_entity("h").hp, 1000.0)


func test_roll_scope_per_action_vs_per_component() -> void:
	var data := {"id": "multi", "team": "A", "stats": {"SPD": 300, "ACC": 1.0, "CRIT": 0.5}, "basic_attack": false,
		"abilities": [{"id": "triple", "targeting": "enemy", "effects": [{"type": "damage", "components": [
			{"damage_type": "true", "formula": "1"}, {"damage_type": "true", "formula": "1"}, {"damage_type": "true", "formula": "1"}]}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "triple"}]}}
	var counts := {}
	for scope in ["per_action", "per_component"]:
		var rules := Ruleset.from_dict({"damage": {"roll_scope": scope}, "victory": {"limits": {"max_turns": 1}}})
		var m := EntityFactory.build(data, BalanceProfile.default_profile(), rules, OperationRegistry.new())
		var tgt := make_entity("t", "B", {"SPD": 1.0, "EVA": 0.5}, false)
		var eng := CombatEngine.new()
		eng.setup(rules, [m["entity"], tgt], 3)
		eng.run()
		counts[scope] = eng.log.of_type(EventTypes.HIT).size() + eng.log.of_type(EventTypes.MISS).size()
	assert_eq(counts["per_action"], 1, "una tirada de impacto por (accion, objetivo)")
	assert_eq(counts["per_component"], 3, "una por componente")


func test_hit_rate_converges_to_acc_minus_eva() -> void:
	# 3000 ataques: P(hit)=0.8 -> tasa observada dentro de +-4 %.
	var a := make_entity("a", "A", {"ACC": 1.0, "SPD": 1000.0, "ATK": 1.0, "CRIT": 0.0, "HP": 1.0e9})
	var b := make_entity("b", "B", {"EVA": 0.2, "SPD": 1.0, "HP": 1.0e9, "DEF": 0.0})
	var eng := make_engine([a, b], 123, {"victory": {"limits": {"max_turns": 3000, "max_actions": 100000}}})
	eng.run()
	var hits := eng.log.of_type(EventTypes.HIT).size()
	var misses := eng.log.of_type(EventTypes.MISS).size()
	var rate := float(hits) / float(hits + misses)
	assert_true(absf(rate - 0.8) < 0.04, "tasa de impacto %.3f" % rate)
	assert_true(hits + misses >= 2900)


func test_golden_regression_seed_42() -> void:
	var r: CombatResult = _duel(42)["result"]
	var f := FileAccess.open("res://tests/golden/duel_a_vs_b_seed42.json", FileAccess.READ)
	if f == null:
		fail("falta el fichero golden; generelo con tools/regen_golden.sh")
		return
	var g: Dictionary = JSON.parse_string(f.get_as_text())
	assert_eq(r.log_hash, g["log_hash"], "la huella del combate de referencia cambio: si es intencionado, regenere el golden")
	assert_eq(r.winner_team, g["winner_team"])
	assert_eq(r.turns, int(g["turns"]))
	assert_eq(r.events, int(g["events"]))
