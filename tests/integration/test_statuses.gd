extends TestCase
## Fase 3.1: estados, duraciones, politicas de reaplicacion, restricciones de uso,
## recursos, iniciativa, canalizacion y pasivas.

const S := Ruleset.TIME_SCALE
var rules := Ruleset.from_dict({})


func _ent(id: String, team: String, data: Dictionary = {}) -> CombatEntity:
	var d := {"id": id, "team": team, "basic_attack": false, "ai": {"type": "passive"}}
	d.merge(data, true)
	var b := EntityFactory.build(d, BalanceProfile.default_profile(), rules, OperationRegistry.new())
	assert_true(b["errors"].is_empty(), "%s: %s" % [id, str(b["errors"])])
	return b["entity"]


func _eng(ents: Array, seed_value: int = 1, over: Dictionary = {}) -> CombatEngine:
	var r := {"victory": {"limits": {"max_turns": 12}}}
	r.merge(over, true)
	var eng := CombatEngine.new()
	var errs := eng.setup(Ruleset.from_dict(r), ents, seed_value)
	assert_eq(errs, [], "setup")
	return eng


func _caster_with(abilities: Array, extra: Dictionary = {}) -> CombatEntity:
	var rules_ai := []
	for a in abilities:
		rules_ai.append({"ability": a["id"], "target": "self" if str(a.get("targeting", "enemy")) == "self" else "first_enemy"})
	var d := {"stats": {"SPD": 200, "ACC": 1.0}, "abilities": abilities, "ai": {"type": "priority_list", "rules": rules_ai}}
	d.merge(extra, true)
	return _ent("a", "A", d)


func _target(extra: Dictionary = {}) -> CombatEntity:
	var d := {"stats": {"SPD": 100, "HP": 5000, "EVA": 0.0}}
	d.merge(extra, true)
	return _ent("b", "B", d)


func _apply_ability(status: String, extra: Dictionary = {}, id: String = "curse") -> Dictionary:
	var eff := {"type": "apply_status", "status": status}
	eff.merge(extra, true)
	return {"id": id, "targeting": "enemy", "uses_per_combat": 1, "effects": [eff]}


func _events(eng: CombatEngine, type: String) -> Array:
	return eng.log.of_type(type)


# --- catalogo nativo ------------------------------------------------------------------------

func test_native_catalog_loads_all_statuses() -> void:
	var cat := StatusCatalog.new()
	assert_eq(cat.load_native(OperationRegistry.new()), [])
	assert_eq(cat.ids(), ["bleed", "burn", "freeze", "poison", "regen", "silence", "stun", "taunt"])


func test_status_def_validation() -> void:
	var reg := OperationRegistry.new()
	var bad := {
		"x": {"id": "x", "poder": 1},
		"politica": {"id": "x", "stacking": {"policy": "magia"}},
		"duracion": {"id": "x", "duration": {"unit": "siglos", "amount": 1}},
		"modifier": {"id": "x", "modifiers": [{"stat": "ATK", "kind": "raro", "value": 1}]},
		"flag": {"id": "x", "flags": {"vuela": true}},
		"periodic": {"id": "x", "periodic": [{"on": "siempre", "effects": [{"type": "heal", "formula": "1"}]}]},
		"effect": {"id": "x", "on_apply": [{"type": "teleport"}]},
		"defense": {"id": "x", "defense": {"escudo_magico": {}}},
		"max_stacks": {"id": "x", "stacking": {"policy": "stack_intensity", "max_stacks": 500}},
	}
	for k in bad:
		var r := StatusDef.from_dict(bad[k], reg)
		assert_true(r["def"] == null, "debe rechazar: %s" % k)
		assert_true(r["errors"].size() > 0)
	assert_true(StatusDef.from_dict({"id": "ok"}, reg)["def"] != null)


func test_unknown_status_reference_rejected_at_setup() -> void:
	var c := _caster_with([_apply_ability("inventado")])
	var eng := CombatEngine.new()
	var errs := eng.setup(rules, [c, _target()], 1)
	assert_true(errs.size() > 0)
	assert_contains(" ".join(errs), "inventado")


# --- duraciones y efectos periodicos ----------------------------------------------------------

func _rot_def(extra: Dictionary = {}) -> Dictionary:
	var d := {"id": "rot", "duration": 2, "periodic": [{"on": "turn_end", "effects": [
		{"type": "damage", "always_hit": true, "can_crit": false, "components": [{"damage_type": "true", "formula": "10"}]}]}]}
	d.merge(extra, true)
	return d


func test_target_turns_duration_counts_exactly_n_turns() -> void:
	var a := _caster_with([_apply_ability("rot")], {"statuses": [_rot_def()]})
	var b := _target()
	var eng := _eng([a, b])
	eng.run()
	var dots := _events(eng, EventTypes.DAMAGE_DEALT).filter(func(e): return e["target"] == "b")
	assert_eq(dots.size(), 2, "2 turnos de b = 2 ticks")
	assert_eq(_events(eng, EventTypes.STATUS_EXPIRED).size(), 1)
	assert_eq(b.statuses.size(), 0)
	assert_almost(b.hp, 5000.0 - 20.0)
	# orden: aplicado -> tick -> tick -> expirado
	var seq: Array = []
	for ev in eng.log.events:
		if ev["type"] in [EventTypes.STATUS_APPLIED, EventTypes.DAMAGE_DEALT, EventTypes.STATUS_EXPIRED]:
			seq.append(ev["type"])
	assert_eq(seq, ["status_applied", "damage_dealt", "damage_dealt", "status_expired"])


func test_status_applied_on_own_turn_skips_current_turn() -> void:
	# a se aplica el estado a si mismo en SU turno con 1 turno de duracion: afecta al siguiente turno completo.
	var ab := {"id": "buff", "targeting": "self", "uses_per_combat": 1, "effects": [{"type": "apply_status", "status": "boost"}]}
	var boost := {"id": "boost", "duration": 1, "modifiers": [{"stat": "ATK", "kind": "flat", "value": 50}]}
	var a := _caster_with([ab], {"statuses": [boost]})
	var eng := _eng([a, _target()], 1, {"victory": {"limits": {"max_turns": 3}}})
	var seen: Array = []
	eng.dispatcher.observe(EventTypes.TURN_STARTED, func(ev: CombatEvent, g: CombatEngine):
		if ev.source_id == "a":
			seen.append(g.get_entity("a").stats.get_value("ATK")), 0, "t")
	eng.run()
	assert_eq(seen, [100.0, 150.0], "aplicado en el turno 1 (no cuenta); activo durante todo el turno 2")
	assert_eq(_events(eng, EventTypes.STATUS_EXPIRED)[0]["time"], 10 * S, "caduca al final del turno 2")


func test_policy_refresh_stack_duration_independent_replace() -> void:
	var defs := [
		{"id": "p_refresh", "duration": 3, "stacking": {"policy": "refresh"}},
		{"id": "p_stackdur", "duration": 3, "stacking": {"policy": "stack_duration"}},
		{"id": "p_indep", "duration": 3, "stacking": {"policy": "independent", "max_stacks": 2}},
		{"id": "p_replace", "duration": 3, "stacking": {"policy": "replace"}},
		{"id": "p_ignore", "duration": 3, "stacking": {"policy": "ignore"}},
		{"id": "p_intens", "duration": 3, "stacking": {"policy": "stack_intensity", "max_stacks": 3}, "modifiers": [{"stat": "DEF", "kind": "flat", "value": -10}]},
	]
	var a := _ent("a", "A", {"statuses": defs})
	var b := _target()
	var eng := _eng([a, b])
	eng.start()
	var svc := eng.status_service
	# refresh: una instancia, duracion reiniciada
	var r1: Dictionary = svc.apply("p_refresh", b, a)
	b.statuses[0].duration.remaining = 1.0
	var r2: Dictionary = svc.apply("p_refresh", b, a)
	assert_eq(r2["result"], "refreshed")
	assert_eq(b.statuses.size(), 1)
	assert_almost(b.statuses[0].duration.remaining, 3.0)
	# stack_duration: suma
	svc.apply("p_stackdur", b, a)
	var r3: Dictionary = svc.apply("p_stackdur", b, a)
	assert_eq(r3["result"], "extended")
	assert_almost((r3["instance"] as StatusInstance).duration.remaining, 6.0)
	# independent: hasta 2 instancias
	svc.apply("p_indep", b, a)
	svc.apply("p_indep", b, a)
	var r4: Dictionary = svc.apply("p_indep", b, a)
	assert_eq(r4["result"], "rejected")
	assert_eq(b.statuses.filter(func(s): return s.def.id == "p_indep").size(), 2)
	# replace: sigue habiendo una, nueva seq
	var first: StatusInstance = svc.apply("p_replace", b, a)["instance"]
	var second: StatusInstance = svc.apply("p_replace", b, a)["instance"]
	assert_eq(b.statuses.filter(func(s): return s.def.id == "p_replace").size(), 1)
	assert_true(second.seq > first.seq)
	# ignore
	svc.apply("p_ignore", b, a)
	assert_eq(svc.apply("p_ignore", b, a)["result"], "rejected")
	# stack_intensity: modificadores escalan con las pilas y respetan el maximo
	for i in 5:
		svc.apply("p_intens", b, a)
	assert_eq(b.status_stacks("p_intens"), 3)
	assert_almost(b.stats.get_value("DEF"), 100.0 - 30.0)
	assert_eq(r1["result"], "applied")


func test_keep_strongest_policy() -> void:
	var a := _ent("a", "A", {"statuses": [{"id": "ks", "duration": 3, "stacking": {"policy": "keep_strongest"}}]})
	var b := _target()
	var eng := _eng([a, b])
	eng.start()
	var svc := eng.status_service
	svc.apply("ks", b, a, {"magnitude": 5.0})
	assert_eq(svc.apply("ks", b, a, {"magnitude": 3.0})["result"], "rejected", "mas debil: se conserva la actual")
	assert_almost(b.statuses[0].magnitude, 5.0)
	assert_eq(svc.apply("ks", b, a, {"magnitude": 9.0})["result"], "applied", "mas fuerte: sustituye")
	assert_eq(b.statuses.size(), 1)
	assert_almost(b.statuses[0].magnitude, 9.0)


func test_duration_unit_global_actions_time_events_permanent() -> void:
	var defs := [
		{"id": "d_global", "duration": {"unit": "global_actions", "amount": 2}},
		{"id": "d_time", "duration": {"unit": "time", "amount": 7}},
		{"id": "d_events", "duration": {"unit": "events", "amount": 2, "event": "hit", "filter": {"target": "self"}}},
		{"id": "d_perm", "duration": {"unit": "permanent"}},
	]
	var a := _ent("a", "A", {"stats": {"SPD": 100, "ACC": 1.0}, "basic_attack": true, "statuses": defs,
		"ai": {"type": "priority_list", "rules": [{"ability": "basic_attack"}]}})
	var b := _target({"stats": {"SPD": 100, "HP": 99999, "EVA": 0.0}, "basic_attack": true, "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack"}]}})
	var eng := _eng([a, b], 1, {"victory": {"limits": {"max_turns": 10, "stagnation_turns": 99}}})
	eng.start()
	for id in ["d_global", "d_time", "d_events", "d_perm"]:
		eng.status_service.apply(id, b, a)
	eng.run()
	# t=10 a actua (b recibe hit 1), b actua en 10 (a recibe)...: events cuenta golpes que b recibe
	var expired: Array = _events(eng, EventTypes.STATUS_EXPIRED).map(func(e): return e["data"]["status"])
	assert_contains(expired, "d_global")
	assert_contains(expired, "d_time")
	assert_contains(expired, "d_events")
	assert_false(expired.has("d_perm"), "permanente no caduca")
	var times := {}
	for e in _events(eng, EventTypes.STATUS_EXPIRED):
		times[e["data"]["status"]] = e["time"]
	assert_eq(times["d_time"], 7 * S, "caduca exactamente en t=7")
	# global_actions=2: caduca al resolverse la 2a accion (a@10, b@10 -> t=10)
	assert_eq(times["d_global"], 10 * S)
	# events=2 golpes recibidos por b: a@10 (1), a@20 (2) -> t=20
	assert_eq(times["d_events"], 20 * S)
	assert_eq(b.statuses.size(), 1)


func test_caster_turns_duration() -> void:
	var a := _caster_with([_apply_ability("c_buff", {"duration": {"unit": "caster_turns", "amount": 2}})], {"statuses": [{"id": "c_buff"}]})
	var eng := _eng([a, _target()])
	eng.run()
	var exp := _events(eng, EventTypes.STATUS_EXPIRED)
	assert_eq(exp.size(), 1)
	# a (SPD 200) actua cada 5 u.t. Aplica en t=5 (su turno, no cuenta); caduca al final de su 2o turno posterior: t=15.
	assert_eq(exp[0]["time"], 15 * S)


func test_modifiers_scale_and_are_removed_on_expiry() -> void:
	var st := {"id": "weak", "duration": 1, "modifiers": [{"stat": "HP", "kind": "flat", "value": -500}]}
	var a := _caster_with([_apply_ability("weak")], {"statuses": [st]})
	var b := _target({"stats": {"SPD": 100, "HP": 1000}})
	var eng := _eng([a, b])
	eng.run()
	assert_almost(b.hp_max(), 1000.0, 1e-9, "tras caducar el HP max vuelve")
	var hp_changes := _events(eng, EventTypes.HP_CHANGED).filter(func(e): return e["data"]["reason"] == "max_hp_changed")
	assert_eq(hp_changes.size(), 1, "al bajar HP max la vida se acota con evento trazable")
	assert_almost(hp_changes[0]["data"]["new"], 500.0)


func test_stun_skips_turns_and_ticks_down() -> void:
	var a := _caster_with([_apply_ability("stun")])
	var b := _target({"basic_attack": true, "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack"}]}})
	var eng := _eng([a, b], 1, {"victory": {"limits": {"max_turns": 8}}})
	eng.run()
	var skipped := _events(eng, EventTypes.TURN_SKIPPED)
	assert_eq(skipped.size(), 1, "stun de 1 turno = 1 turno perdido")
	assert_eq(skipped[0]["source"], "b")
	assert_eq(_events(eng, EventTypes.STATUS_EXPIRED).size(), 1, "caduca aunque el turno se omita")
	var b_acts := _events(eng, EventTypes.ACTION_RESOLVED).filter(func(e): return e["source"] == "b")
	assert_true(b_acts.size() >= 1, "luego vuelve a actuar")


func test_silence_blocks_tagged_abilities() -> void:
	var spell := {"id": "bolt", "targeting": "enemy", "tags": ["spell"], "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "1"}]}]}
	var punch := {"id": "punch", "targeting": "enemy", "tags": ["melee"], "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "1"}]}]}
	var a := _ent("a", "A", {"abilities": [spell, punch], "ai": {"type": "priority_list", "rules": [{"ability": "bolt"}, {"ability": "punch"}]}})
	var b := _target()
	var eng := _eng([a, b])
	eng.start()
	eng.status_service.apply("silence", a, b)
	var view := ViewBuilder.build(eng, a, TurnState.new(a, 1))
	var legal: Array = view["legal_actions"].map(func(x): return x["ability_id"])
	assert_eq(legal, ["punch"], "silencio bloquea la etiqueta spell")
	var reason := ActionValidator.validate(eng, a, TurnState.new(a, 1), AIDecision.use("bolt", ["b"]))
	assert_contains(reason, "bloqueada:silence")


func test_taunt_restricts_enemy_targeting_unless_ignored() -> void:
	var hit := {"id": "hit", "targeting": "enemy", "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "1"}]}]}
	var snipe := {"id": "snipe", "targeting": "enemy", "ignore_taunt": true, "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "1"}]}]}
	var a := _ent("a", "A", {"abilities": [hit, snipe]})
	var b1 := _ent("b1", "B")
	var b2 := _ent("b2", "B")
	var eng := _eng([a, b1, b2])
	eng.start()
	eng.status_service.apply("taunt", b2, b2)
	assert_eq(ActionValidator.valid_targets(eng, a, a.get_ability("hit")), ["b2"])
	assert_eq(ActionValidator.valid_targets(eng, a, a.get_ability("snipe")), ["b1", "b2"])


func test_status_immunity_by_tag() -> void:
	var a := _ent("a", "A", {"statuses": [{"id": "ward", "duration": {"unit": "permanent"}, "flags": {"immune_status_tags": ["cc"]}}]})
	var b := _target()
	var eng := _eng([a, b])
	eng.start()
	eng.status_service.apply("ward", b, b)
	var r: Dictionary = eng.status_service.apply("stun", b, a)
	assert_eq(r["result"], "rejected")
	assert_eq(_events(eng, EventTypes.STATUS_REJECTED).size(), 1)
	assert_contains(_events(eng, EventTypes.STATUS_REJECTED)[0]["data"]["reason"], "immune:ward")
	assert_eq(eng.status_service.apply("poison", b, a)["result"], "applied", "otras etiquetas siguen")


func test_apply_can_be_cancelled_by_interceptor() -> void:
	var a := _ent("a", "A")
	var b := _target()
	var eng := _eng([a, b])
	eng.start()
	eng.dispatcher.intercept(EventTypes.STATUS_APPLIED, func(ev: CombatEvent, _g): ev.cancel("barrera"), 0, "x")
	assert_eq(eng.status_service.apply("poison", b, a)["result"], "rejected")
	assert_eq(b.statuses.size(), 0)


func test_suspend_initiative_status() -> void:
	var a := _ent("a", "A", {"statuses": [{"id": "frozen_time", "duration": {"unit": "permanent"}, "flags": {"suspend_initiative": true}}]})
	var b := _target()
	var eng := _eng([a, b])
	eng.start()
	eng.status_service.apply("frozen_time", b, a)
	assert_true(b.is_suspended())
	assert_eq(eng.scheduler.time_until_ready(b), AtbScheduler.NEVER)
	eng.status_service.dispel(b, {"status": "frozen_time"}, "test", 0)
	assert_false(b.is_suspended())


func test_death_clears_statuses() -> void:
	var a := _ent("a", "A", {"stats": {"ATK": 9999, "SPD": 300, "ACC": 1.0}, "basic_attack": true, "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack"}]}})
	var b := _target({"stats": {"HP": 10, "SPD": 1}})
	var eng := _eng([a, b])
	eng.start()
	eng.status_service.apply("poison", b, a)
	eng.run()
	assert_false(b.alive)
	assert_eq(b.statuses.size(), 0)
	assert_eq(_events(eng, EventTypes.STATUS_REMOVED).filter(func(e): return e["data"]["reason"] == "death").size(), 1)


# --- disipar, extender, transferir -------------------------------------------------------------------

func test_dispel_filters_and_non_dispellable() -> void:
	var defs := [
		{"id": "d1", "tags": ["curse"], "duration": 5}, {"id": "d2", "tags": ["curse"], "duration": 5},
		{"id": "good", "beneficial": true, "duration": 5}, {"id": "stuck", "tags": ["curse"], "dispellable": false, "duration": 5},
	]
	var a := _ent("a", "A", {"statuses": defs})
	var b := _target()
	var eng := _eng([a, b])
	eng.start()
	for id in ["d1", "d2", "good", "stuck"]:
		eng.status_service.apply(id, b, a)
	assert_eq(eng.status_service.dispel(b, {"tags": ["curse"], "count": 1}, "t", 0).size(), 1, "count limita")
	assert_eq(eng.status_service.dispel(b, {"tags": ["curse"]}, "t", 0).size(), 1, "quita d2; stuck no es disipable")
	assert_eq(b.statuses.map(func(s): return s.def.id), ["good", "stuck"])
	assert_eq(eng.status_service.dispel(b, {"beneficial": true}, "t", 0).size(), 1)
	assert_eq(eng.status_service.dispel(b, {"tags": ["curse"], "force": true}, "t", 0).size(), 1, "force ignora dispellable")


func test_remove_and_extend_operations() -> void:
	var ext := {"id": "ext", "targeting": "enemy", "effects": [{"type": "extend_status", "status": "slow", "amount": 2}]}
	var shr := {"id": "shr", "targeting": "enemy", "effects": [{"type": "extend_status", "status": "slow", "amount": -9}]}
	var a := _ent("a", "A", {"abilities": [ext, shr], "statuses": [{"id": "slow", "duration": 3, "modifiers": [{"stat": "SPD", "kind": "mult", "value": 0.5}]}]})
	var b := _target()
	var eng := _eng([a, b])
	eng.start()
	eng.status_service.apply("slow", b, a)
	assert_almost(b.stats.get_value("SPD"), 50.0)
	var t := TurnState.new(a, 1)
	ActionResolver.resolve(eng, t, a, a.get_ability("ext"), [b] as Array[CombatEntity], 0)
	assert_almost(b.statuses[0].duration.remaining, 5.0)
	ActionResolver.resolve(eng, t, a, a.get_ability("shr"), [b] as Array[CombatEntity], 0)
	assert_eq(b.statuses.size(), 0, "acortar mas que lo restante lo expira")
	assert_almost(b.stats.get_value("SPD"), 100.0, 1e-9, "y retira sus modificadores")


func test_transfer_steal_copy_give() -> void:
	var defs := [{"id": "buff1", "beneficial": true, "duration": 4, "tags": ["buff"], "modifiers": [{"stat": "ATK", "kind": "flat", "value": 20}]}]
	var steal := {"id": "steal", "targeting": "enemy", "effects": [{"type": "transfer_status", "mode": "steal", "tags": ["buff"]}]}
	var copy := {"id": "copy", "targeting": "enemy", "effects": [{"type": "transfer_status", "mode": "copy", "tags": ["buff"]}]}
	var give := {"id": "give", "targeting": "enemy", "effects": [{"type": "transfer_status", "mode": "give", "status": "buff1"}]}
	var a := _ent("a", "A", {"abilities": [steal, copy, give], "statuses": defs})
	var b := _target()
	var eng := _eng([a, b])
	eng.start()
	var t := TurnState.new(a, 1)
	eng.status_service.apply("buff1", b, b)
	b.statuses[0].duration.remaining = 2.0
	ActionResolver.resolve(eng, t, a, a.get_ability("copy"), [b] as Array[CombatEntity], 0)
	assert_eq(a.status_stacks("buff1"), 1)
	assert_eq(b.status_stacks("buff1"), 1, "copiar no quita")
	assert_almost(a.statuses[0].duration.remaining, 2.0, 1e-9, "conserva la duracion restante")
	eng.status_service.dispel(a, {"status": "buff1"}, "t", 0)
	ActionResolver.resolve(eng, t, a, a.get_ability("steal"), [b] as Array[CombatEntity], 0)
	assert_eq(a.status_stacks("buff1"), 1)
	assert_eq(b.status_stacks("buff1"), 0, "robar quita al objetivo")
	assert_almost(a.stats.get_value("ATK"), 120.0)
	ActionResolver.resolve(eng, t, a, a.get_ability("give"), [b] as Array[CombatEntity], 0)
	assert_eq(a.status_stacks("buff1"), 0)
	assert_eq(b.status_stacks("buff1"), 1, "dar mueve al objetivo")


# --- restricciones de uso -------------------------------------------------------------------------------

func _count_resolved(eng: CombatEngine, who: String, ability: String) -> int:
	return _events(eng, EventTypes.ACTION_RESOLVED).filter(func(e): return e["source"] == who and e["data"]["ability"] == ability).size()


func _dmg(id: String, extra: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "targeting": "enemy", "effects": [{"type": "damage", "always_hit": true, "can_crit": false, "components": [{"damage_type": "true", "formula": "1"}]}]}
	d.merge(extra, true)
	return d


func test_cooldown_in_turns() -> void:
	var a := _caster_with([_dmg("nuke", {"cooldown": 3})])
	var eng := _eng([a, _target()], 1, {"victory": {"limits": {"max_turns": 20, "stagnation_turns": 99}}})
	eng.run()
	# a juega 1 de cada 2 turnos globales (SPD 200 vs 100): turnos de a: 1,2,3...  cooldown 3 => usa en sus turnos 1, 4, 7...
	var times := _events(eng, EventTypes.ACTION_RESOLVED).filter(func(e): return e["source"] == "a").map(func(e): return e["time"])
	assert_true(times.size() >= 2)
	assert_eq(times[1] - times[0], 15 * S, "3 turnos de a (5 u.t. cada uno) entre usos")


func test_uses_per_combat_and_per_turn_with_free_actions() -> void:
	var a := _caster_with([_dmg("once", {"uses_per_combat": 2}), _dmg("free2", {"action_type": "free", "uses_per_turn": 2})])
	var eng := _eng([a, _target()], 1, {"victory": {"limits": {"max_turns": 10, "stagnation_turns": 99}}})
	eng.run()
	assert_eq(_count_resolved(eng, "a", "once"), 2, "usos por combate")
	# free2: 2 veces por turno global; el turno termina cuando no hay mas acciones legales
	var a_turns := _events(eng, EventTypes.TURN_STARTED).filter(func(e): return e["source"] == "a").size()
	assert_true(_count_resolved(eng, "a", "free2") >= 2)
	assert_true(_count_resolved(eng, "a", "free2") <= 2 * a_turns, "no mas de 2 por turno")


func test_charges_and_recharge() -> void:
	var a := _caster_with([_dmg("shot", {"charges": {"max": 2, "initial": 2, "recharge": {"unit": "target_turns", "amount": 2}}})])
	var eng := _eng([a, _target()], 1, {"victory": {"limits": {"max_turns": 14, "stagnation_turns": 99}}})
	eng.run()
	var times := _events(eng, EventTypes.ACTION_RESOLVED).filter(func(e): return e["source"] == "a").map(func(e): return e["time"] / S)
	# 2 cargas iniciales: t=5 y t=10; la recarga empieza al gastar la primera (turno 1) y tarda 2 turnos de a.
	assert_true(times.size() >= 3, str(times))
	assert_eq(times[0], 5)
	assert_eq(times[1], 10)
	assert_true(times[2] > 10, "tercer uso solo tras recargar")


func test_requires_self_and_target_conditions() -> void:
	var finisher := _dmg("finisher", {"requires": {"target.hp_ratio": {"lt": 0.5}}})
	var rage := _dmg("rage", {"requires": {"self.hp_ratio": {"lt": 0.5}}})
	var a := _ent("a", "A", {"abilities": [finisher, rage]})
	var b := _target({"stats": {"HP": 1000, "SPD": 1}})
	var eng := _eng([a, b])
	eng.start()
	var t := TurnState.new(a, 1)
	assert_eq(ViewBuilder.build(eng, a, t)["legal_actions"].size(), 0)
	b.hp = 400.0
	var legal: Array = ViewBuilder.build(eng, a, t)["legal_actions"].map(func(x): return x["ability_id"])
	assert_eq(legal, ["finisher"], "target.hp_ratio < 0.5")
	a.hp = 100.0
	legal = ViewBuilder.build(eng, a, t)["legal_actions"].map(func(x): return x["ability_id"])
	assert_eq(legal, ["finisher", "rage"])


func test_requires_status_condition() -> void:
	var combo := _dmg("combo", {"requires": {"target.status.stun": {"ge": 1}}})
	var a := _ent("a", "A", {"abilities": [combo]})
	var b := _target()
	var eng := _eng([a, b])
	eng.start()
	var t := TurnState.new(a, 1)
	assert_eq(ViewBuilder.build(eng, a, t)["legal_actions"].size(), 0)
	eng.status_service.apply("stun", b, a)
	assert_eq(ViewBuilder.build(eng, a, t)["legal_actions"].size(), 1)


func test_ability_restriction_validation() -> void:
	var reg := OperationRegistry.new()
	var base := {"id": "x"}
	var bad := {
		"cooldown": {"cooldown": 0}, "cd_unit": {"cooldown": {"unit": "permanent"}},
		"uses": {"uses_per_combat": 0}, "charges": {"charges": {"max": 0}}, "charges_init": {"charges": {"max": 2, "initial": 5}},
		"requires": {"requires": {"yo.hp": {"lt": 1}}}, "requires_op": {"requires": {"self.hp": {"cerca": 1}}},
		"req_event": {"requires": {"event.amount": {"gt": 1}}}, "cast": {"cast_time": -1}, "trigger_noevent": {"trigger": {}},
	}
	var seen := 0
	for k in bad:
		var d := base.duplicate()
		var spec: Dictionary = bad[k]
		if k == "cd_unit":
			d["cooldown"] = spec["cooldown"]
		else:
			d.merge(spec, true)
		var r := AbilityDef.from_dict(d, reg)
		assert_true(r["ability"] == null, "debe rechazar: %s" % k)
		seen += 1
	assert_eq(seen, bad.size())


# --- recursos e iniciativa --------------------------------------------------------------------------------

func test_resource_regen_limits_and_modify_resource() -> void:
	var res := {"fury": {"initial": 0, "max": 10, "regen_per_turn": 4}}
	var a := _ent("a", "A", {"resources": res, "stats": {"SPD": 100}})
	var eng := _eng([a, _target()], 1, {"victory": {"limits": {"max_turns": 6, "stagnation_turns": 99}}})
	eng.run()
	var limits := _events(eng, EventTypes.RESOURCE_LIMIT)
	assert_true(limits.size() >= 1)
	assert_eq(limits[0]["data"]["limit"], "max")
	assert_almost((a.get_resource("fury") as ResourceState).value, 10.0)
	var regen := _events(eng, EventTypes.RESOURCE_CHANGED).filter(func(e): return e["data"]["reason"] == "regen")
	assert_almost(regen[0]["data"]["delta"], 4.0)
	assert_almost(regen[2]["data"]["delta"], 2.0, 1e-9, "el tercer tic se acota al maximo (8+2)")


func test_modify_resource_operation_modes() -> void:
	var ops := [
		{"id": "gain", "targeting": "self", "effects": [{"type": "modify_resource", "resource": "mana", "amount": "30"}]},
		{"id": "drain", "targeting": "enemy", "effects": [{"type": "modify_resource", "resource": "mana", "amount": "-25"}]},
		{"id": "fill", "targeting": "self", "effects": [{"type": "modify_resource", "resource": "mana", "mode": "set", "amount": "caster.res.mana.max"}]},
		{"id": "grow", "targeting": "self", "effects": [{"type": "modify_resource", "resource": "mana", "property": "max", "amount": "50"}]},
	]
	var a := _ent("a", "A", {"abilities": ops, "resources": {"mana": {"initial": 10, "max": 100}}})
	var b := _target({"resources": {"mana": {"initial": 20, "max": 100}}})
	var eng := _eng([a, b])
	eng.start()
	var t := TurnState.new(a, 1)
	var cast := func(id: String, tgt: CombatEntity): ActionResolver.resolve(eng, t, a, a.get_ability(id), [tgt] as Array[CombatEntity], 0)
	cast.call("gain", a)
	assert_almost((a.get_resource("mana") as ResourceState).value, 40.0)
	cast.call("drain", b)
	assert_almost((b.get_resource("mana") as ResourceState).value, 0.0, 1e-9, "acotado al minimo")
	assert_true(_events(eng, EventTypes.RESOURCE_LIMIT).any(func(e): return e["target"] == "b" and e["data"]["limit"] == "min"))
	cast.call("fill", a)
	assert_almost((a.get_resource("mana") as ResourceState).value, 100.0)
	cast.call("grow", a)
	assert_almost((a.get_resource("mana") as ResourceState).max_value, 150.0)


func test_modify_initiative_modes() -> void:
	var ops := [
		{"id": "add", "targeting": "enemy", "effects": [{"type": "modify_initiative", "mode": "add", "amount": "-300"}]},
		{"id": "steal", "targeting": "enemy", "effects": [{"type": "modify_initiative", "mode": "steal", "amount": "400"}]},
		{"id": "extra", "targeting": "self", "effects": [{"type": "modify_initiative", "mode": "extra_turn"}]},
		{"id": "set", "targeting": "enemy", "effects": [{"type": "modify_initiative", "mode": "set", "amount": "10"}]},
	]
	var a := _ent("a", "A", {"abilities": ops})
	var b := _target()
	var eng := _eng([a, b], 1, {}, )
	eng.start()
	b.initiative_micro = 500 * S
	var t := TurnState.new(a, 1)
	var cast := func(id: String, tgt: CombatEntity): ActionResolver.resolve(eng, t, a, a.get_ability(id), [tgt] as Array[CombatEntity], 0)
	cast.call("add", b)
	assert_eq(b.initiative_micro, 200 * S, "retrasar")
	cast.call("steal", b)
	assert_eq(b.initiative_micro, 0, "no se roba mas de lo que hay")
	assert_eq(a.initiative_micro, 200 * S)
	cast.call("extra", a)
	assert_eq(a.initiative_micro, 1200 * S, "extra_turn suma el umbral")
	cast.call("set", b)
	assert_eq(b.initiative_micro, 10 * S)
	cast.call("add", b)
	assert_eq(b.initiative_micro, 0, "nunca negativa")
	assert_true(_events(eng, EventTypes.INITIATIVE_CHANGED).size() >= 6)


func test_extra_turn_grants_immediate_action() -> void:
	var extra := {"id": "extra", "targeting": "self", "uses_per_combat": 1, "effects": [{"type": "modify_initiative", "mode": "extra_turn"}]}
	var a := _caster_with([extra, _dmg("hit")])
	var eng := _eng([a, _target()], 1, {"victory": {"limits": {"max_turns": 4, "stagnation_turns": 99}}})
	eng.run()
	var a_turns := _events(eng, EventTypes.TURN_STARTED).filter(func(e): return e["source"] == "a").map(func(e): return e["time"])
	assert_eq(a_turns[0], a_turns[1], "el turno extra ocurre en el mismo instante")


# --- probabilidad (procs) ------------------------------------------------------------------------------------

func test_chance_proc_events_and_determinism() -> void:
	var results: Array = []
	for rep in 2:
		var ab := {"id": "maybe", "targeting": "enemy", "effects": [{"type": "apply_status", "status": "stun", "chance": 0.5}]}
		var a := _caster_with([ab])
		var eng := _eng([a, _target()], 7, {"victory": {"limits": {"max_turns": 40, "stagnation_turns": 99}}})
		eng.run()
		var procs := _events(eng, EventTypes.PROC)
		results.append([procs.size(), procs.filter(func(e): return e["data"]["success"]).size(), eng.log.digest()])
		for p in procs:
			assert_true(p["data"]["roll"] >= 0.0 and p["data"]["roll"] < 1.0)
			assert_eq(p["data"]["chance"], 0.5)
	assert_eq(results[0], results[1], "reproducible con la misma semilla")
	assert_true(results[0][0] > 4 and results[0][1] > 0 and results[0][1] < results[0][0], str(results[0]))


func test_chance_zero_and_one() -> void:
	for pair in [[0.0, 0], [1.0, 1]]:
		var ab := {"id": "x", "targeting": "enemy", "uses_per_combat": 1, "effects": [{"type": "apply_status", "status": "poison", "chance": pair[0]}]}
		var a := _caster_with([ab])
		var eng := _eng([a, _target()], 3, {"victory": {"limits": {"max_turns": 2}}})
		eng.run()
		assert_eq(_events(eng, EventTypes.STATUS_APPLIED).size(), pair[1], "chance=%s" % pair[0])


func test_effect_on_caster() -> void:
	var ab := {"id": "drain", "targeting": "enemy", "uses_per_combat": 1, "effects": [
		{"type": "damage", "always_hit": true, "components": [{"damage_type": "true", "formula": "100"}]},
		{"type": "heal", "on": "caster", "formula": "50"}]}
	var a := _caster_with([ab])
	var eng := _eng([a, _target()], 1, {"victory": {"limits": {"max_turns": 2}}}, )
	eng.start()
	a.hp = 500.0
	eng.run()
	assert_almost(a.hp, 550.0)


# --- canalizacion ---------------------------------------------------------------------------------------------

func _channeler(extra: Dictionary = {}) -> CombatEntity:
	var big := _dmg("beam", {"cast_time": 12})
	big["effects"][0]["components"][0]["formula"] = "300"
	var d := {"abilities": [big], "ai": {"type": "priority_list", "rules": [{"ability": "beam"}]}, "stats": {"SPD": 100, "ACC": 1.0}}
	d.merge(extra, true)
	return _ent("a", "A", d)


func test_channel_resolves_after_cast_time_and_suspends_initiative() -> void:
	var a := _channeler()
	var b := _target({"stats": {"SPD": 1, "HP": 5000}})
	var eng := _eng([a, b], 1, {"victory": {"limits": {"max_virtual_time": 40, "stagnation_turns": 999}}})
	eng.run()
	var started := _events(eng, EventTypes.CHANNEL_STARTED)
	var done := _events(eng, EventTypes.CHANNEL_COMPLETED)
	assert_true(started.size() >= 1 and done.size() >= 1)
	assert_eq(started[0]["time"], 10 * S)
	assert_eq(done[0]["time"], 22 * S, "10 + cast_time 12")
	var dealt := _events(eng, EventTypes.DAMAGE_DEALT)
	assert_eq(dealt[0]["time"], 22 * S, "el dano llega al completarse")
	assert_almost(dealt[0]["data"]["amount"], 300.0)
	var a_turns := _events(eng, EventTypes.TURN_STARTED).filter(func(e): return e["source"] == "a").map(func(e): return e["time"])
	assert_false(a_turns.any(func(t): return t > 10 * S and t < 22 * S), "sin turnos mientras canaliza")
	var ended: Dictionary = _events(eng, EventTypes.TURN_ENDED)[0]
	assert_eq(ended["data"]["reason"], "channeling")


func test_channel_interrupted_by_stun_and_by_death() -> void:
	var a := _channeler()
	var b := _target({"stats": {"SPD": 1, "HP": 5000}})
	var eng := _eng([a, b], 1, {"victory": {"limits": {"max_virtual_time": 40, "stagnation_turns": 999}}})
	eng.scheduler.schedule(15 * S, func(e: CombatEngine): e.status_service.apply("stun", e.get_entity("a"), e.get_entity("b")), "stun_a")
	eng.run()
	assert_eq(_events(eng, EventTypes.CHANNEL_INTERRUPTED).size(), 1)
	assert_eq(_events(eng, EventTypes.CHANNEL_COMPLETED).size(), 0)
	assert_eq(_events(eng, EventTypes.DAMAGE_DEALT).filter(func(e): return e["source"] == "a" and e["time"] < 30 * S).size(), 0, "interrumpido: el dano no llega")
	# muerte
	var a2 := _channeler()
	var b2 := _target({"stats": {"SPD": 1, "HP": 5000}})
	var eng2 := _eng([a2, b2], 1, {"victory": {"limits": {"max_virtual_time": 40, "stagnation_turns": 999}}})
	eng2.scheduler.schedule(15 * S, func(e: CombatEngine): e.get_entity("a").hp = 0.0; e.check_all_deaths(), "kill")
	eng2.run()
	assert_eq(_events(eng2, EventTypes.CHANNEL_INTERRUPTED)[0]["data"]["by"], "death")


func test_non_interruptible_channel_resists_stun() -> void:
	var big := _dmg("beam", {"cast_time": 12, "interruptible": false})
	var a := _ent("a", "A", {"abilities": [big], "ai": {"type": "priority_list", "rules": [{"ability": "beam"}]}, "stats": {"SPD": 100, "ACC": 1.0}})
	var b := _target({"stats": {"SPD": 1, "HP": 5000}})
	var eng := _eng([a, b], 1, {"victory": {"limits": {"max_virtual_time": 30, "stagnation_turns": 999}}})
	eng.scheduler.schedule(15 * S, func(e: CombatEngine): e.status_service.apply("stun", e.get_entity("a"), e.get_entity("b")), "stun_a")
	eng.run()
	assert_eq(_events(eng, EventTypes.CHANNEL_INTERRUPTED).size(), 0)
	assert_eq(_events(eng, EventTypes.CHANNEL_COMPLETED).size(), 1)


# --- pasivas ---------------------------------------------------------------------------------------------------

func test_passive_modifiers_apply_and_are_removed_with_ability() -> void:
	var passive := {"id": "tough", "passive": {"modifiers": [{"stat": "DEF", "kind": "flat", "value": 50}, {"stat": "HP", "kind": "pct_add", "value": 0.1}]}}
	var a := _ent("a", "A", {"abilities": [passive]})
	var eng := _eng([a, _target()])
	assert_almost(a.stats.get_value("DEF"), 150.0)
	assert_almost(a.hp_max(), 1100.0)
	eng.remove_ability(a, "tough")
	assert_almost(a.stats.get_value("DEF"), 100.0)
	assert_almost(a.hp_max(), 1000.0)
