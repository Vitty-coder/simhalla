extends TestCase
## Reloj ATB: ganancia proporcional a SPD, exceso, empates, cambios de velocidad.

const S := Ruleset.TIME_SCALE


func _two(spd_a: float, spd_b: float) -> CombatEngine:
	return make_engine([make_entity("a", "A", {"SPD": spd_a}), make_entity("b", "B", {"SPD": spd_b})])


func _turn_order(eng: CombatEngine, turns: int) -> Array:
	var out: Array = []
	eng.start()
	while out.size() < turns:
		eng._begin_next_turn()
		if eng.turn == null:
			break
		out.append([eng.turn.entity.id, float(eng.scheduler.now) / S])
		eng._end_turn("test")
	return out


func test_time_to_threshold_proportional_to_spd() -> void:
	var eng := _two(100.0, 200.0)
	assert_eq(eng.scheduler.time_until_ready(eng.get_entity("a")), 10 * S, "1000/100 = 10 u.t.")
	assert_eq(eng.scheduler.time_until_ready(eng.get_entity("b")), 5 * S, "1000/200 = 5 u.t.")


func test_turn_order_with_different_speeds() -> void:
	var eng := _two(100.0, 200.0)
	var order := _turn_order(eng, 6)
	# b actua en 5; en 10 empatan (iniciativa 1000 ambos) y gana b por SPD; despues a; b en 15 y 20...
	var ids := order.map(func(x): return x[0])
	assert_eq(ids, ["b", "b", "a", "b", "b", "a"], str(order))
	assert_almost(order[0][1], 5.0)
	assert_almost(order[2][1], 10.0, 1e-9, "a llega a 10")


func test_excess_initiative_is_conserved() -> void:
	# SPD 300: 1000/300 = 3.333... -> turno en t=3.333334 con excedente.
	var eng := make_engine([make_entity("a", "A", {"SPD": 300.0}), make_entity("b", "B", {"SPD": 1.0})])
	eng.start()
	eng._begin_next_turn()
	var a := eng.get_entity("a")
	assert_eq(eng.turn.entity.id, "a")
	# iniciativa tras el turno = acumulada - umbral >= 0 (excedente conservado)
	assert_true(a.initiative_micro >= 0 and a.initiative_micro < 1000, "excedente pequeno pero no negativo: %d" % a.initiative_micro)
	assert_eq(eng.scheduler.now, 3333334)
	# Tras 3 turnos el tiempo total debe ser 10.000000 +- 1 microunidad (sin deriva acumulada)
	eng._end_turn("t")
	for i in 2:
		eng._begin_next_turn()
		eng._end_turn("t")
	assert_true(absi(eng.scheduler.now - 10 * S) <= 2, "sin deriva: %d" % eng.scheduler.now)


func test_tie_break_default_excess_then_spd_then_slot() -> void:
	# Mismo SPD e iniciativa: gana el slot menor.
	var eng := _two(100.0, 100.0)
	var order := _turn_order(eng, 4)
	assert_eq(order.map(func(x): return x[0]), ["a", "b", "a", "b"])


func test_tie_break_criteria_are_configurable() -> void:
	# En t=10 empatan a (SPD 100) y b (SPD 200, ya actuo en t=5 y en t=10 tiene 1000 otra vez).
	var by_spd := make_engine([make_entity("a", "A", {"SPD": 100.0}), make_entity("b", "B", {"SPD": 200.0})], 1, {"atb": {"tie_break": ["spd_desc", "slot_asc"]}})
	var o1 := _turn_order(by_spd, 3)
	assert_eq(o1.map(func(x): return x[0]), ["b", "b", "a"], "spd_desc: b antes que a en el empate")
	var by_slot := make_engine([make_entity("a", "A", {"SPD": 100.0}), make_entity("b", "B", {"SPD": 200.0})], 1, {"atb": {"tie_break": ["slot_asc"]}})
	var o2 := _turn_order(by_slot, 3)
	assert_eq(o2.map(func(x): return x[0]), ["b", "a", "b"], "slot_asc: a (slot 0) antes que b en el empate")


func test_tie_break_random_is_reproducible() -> void:
	var rules := {"atb": {"tie_break": ["random"]}}
	var seqs := []
	for i in 2:
		var eng := make_engine([make_entity("a", "A"), make_entity("b", "B"), make_entity("c", "C")], 77, rules)
		seqs.append(_turn_order(eng, 9).map(func(x): return x[0]))
	assert_eq(seqs[0], seqs[1], "misma semilla, mismo orden")


func test_non_positive_spd_gains_nothing() -> void:
	var eng := make_engine([make_entity("a", "A", {"SPD": 0.0}), make_entity("b", "B", {"SPD": -50.0}), make_entity("c", "C", {"SPD": 100.0})])
	assert_eq(eng.scheduler.time_until_ready(eng.get_entity("a")), AtbScheduler.NEVER)
	assert_eq(eng.scheduler.time_until_ready(eng.get_entity("b")), AtbScheduler.NEVER)
	assert_eq(eng.scheduler.time_until_ready(eng.get_entity("c")), 10 * S)
	eng.scheduler.advance(eng.entities, 5 * S)
	assert_eq(eng.get_entity("a").initiative_micro, 0)
	assert_eq(eng.get_entity("b").initiative_micro, 0, "SPD negativa no resta iniciativa (clamp_zero)")
	assert_eq(eng.get_entity("c").initiative_micro, 500 * S)


func test_suspended_initiative_does_not_advance() -> void:
	var eng := _two(100.0, 100.0)
	eng.get_entity("a").initiative_suspended = true
	assert_eq(eng.scheduler.time_until_ready(eng.get_entity("a")), AtbScheduler.NEVER)
	eng.scheduler.advance(eng.entities, 3 * S)
	assert_eq(eng.get_entity("a").initiative_micro, 0)
	assert_eq(eng.get_entity("b").initiative_micro, 300 * S)


func test_instant_extra_turn_when_initiative_over_double() -> void:
	var eng := make_engine([make_entity("a", "A", {"SPD": 100.0}), make_entity("b", "B", {"SPD": 100.0})], 1, {}, EventLog.TraceLevel.FULL, {"a": {"initiative": 2500.0}})
	var order := _turn_order(eng, 3)
	assert_eq(order.map(func(x): return x[0]), ["a", "a", "a"], "con 2500 de iniciativa, a actua 2 veces en t=0 y de nuevo antes que b")
	assert_almost(order[0][1], 0.0)
	assert_almost(order[1][1], 0.0)


func test_timed_events_order_and_times() -> void:
	var eng := _two(100.0, 100.0)
	var fired: Array = []
	eng.scheduler.schedule(3 * S, func(_e): fired.append("t3"), "t3")
	eng.scheduler.schedule(1 * S, func(_e): fired.append("t1b"), "t1b")
	eng.scheduler.schedule(1 * S, func(_e): fired.append("t1c"), "t1c")
	eng.start()
	eng._begin_next_turn()
	assert_eq(fired, ["t1b", "t1c", "t3"], "orden por tiempo y luego por alta")
	assert_eq(eng.turn.entity.id, "a")


func test_speed_change_mid_flight_uses_accumulated_initiative() -> void:
	# a (SPD 100) acumula hasta t=5 (500 pts); entonces su SPD pasa a 500.
	# Restan 500 pts a 500/u.t. = 1 u.t. => turno en t=6 (no en t=10, ni en 5+10).
	var eng := make_engine([make_entity("a", "A", {"SPD": 100.0}), make_entity("b", "B", {"SPD": 1.0})])
	eng.scheduler.schedule(5 * S, func(e): e.get_entity("a").stats.add_modifier(StatModifier.make("SPD", StatModifier.Kind.SET, 500.0, "haste")), "haste")
	eng.start()
	eng._begin_next_turn()
	assert_eq(eng.turn.entity.id, "a")
	assert_eq(eng.scheduler.now, 6 * S)


func test_timed_events_first_flag_at_same_instant() -> void:
	var eng := _two(100.0, 1.0)
	var log: Array = []
	eng.scheduler.schedule(10 * S, func(_e): log.append("timed"), "x")
	eng.start()
	eng._begin_next_turn()
	assert_eq(log, ["timed"], "con timed_events_first=true el evento va antes del turno en t=10")
	var eng2 := make_engine([make_entity("a", "A", {"SPD": 100.0}), make_entity("b", "B", {"SPD": 1.0})], 1, {"atb": {"timed_events_first": false}})
	var log2: Array = []
	eng2.scheduler.schedule(10 * S, func(_e): log2.append("timed"), "x")
	eng2.start()
	eng2._begin_next_turn()
	assert_eq(log2, [], "con false el turno va primero")
	assert_eq(eng2.turn.entity.id, "a")


func test_forecast_matches_actual_order() -> void:
	var eng := _two(100.0, 160.0)
	var fc := eng.forecast(6)
	var order := _turn_order(make_engine([make_entity("a", "A", {"SPD": 100.0}), make_entity("b", "B", {"SPD": 160.0})]), 6)
	assert_eq(fc.map(func(x): return x["id"]), order.map(func(x): return x[0]))
