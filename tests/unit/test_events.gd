extends TestCase
## Eventos: orden estable de suscriptores, intercepcion trazable, limites.


func _eng() -> CombatEngine:
	var eng := make_engine([make_entity("a", "A"), make_entity("b", "B")])
	eng.start()
	return eng


func test_ids_are_monotonic_and_logged() -> void:
	var eng := _eng()
	var e1 := eng.emit("x")
	var e2 := eng.emit("y", "a", "b", {"k": 1}, e1.id)
	assert_true(e2.id > e1.id)
	assert_eq(e2.cause_id, e1.id)
	var logged := eng.log.of_type("y")
	assert_eq(logged.size(), 1)
	assert_eq(logged[0]["data"]["k"], 1)


func test_interceptor_priority_order_is_stable() -> void:
	var eng := _eng()
	var order: Array = []
	eng.dispatcher.intercept("t", func(_e, _g): order.append("p5"), 5, "o")
	eng.dispatcher.intercept("t", func(_e, _g): order.append("p0-first"), 0, "o")
	eng.dispatcher.intercept("t", func(_e, _g): order.append("p0-second"), 0, "o")
	eng.dispatcher.intercept("t", func(_e, _g): order.append("pm1"), -1, "o")
	eng.emit("t", "", "", {}, 0, CombatEvent.Phase.PRE)
	assert_eq(order, ["pm1", "p0-first", "p0-second", "p5"])


func test_modification_is_traceable_not_silent() -> void:
	var eng := _eng()
	eng.dispatcher.intercept("t", func(ev: CombatEvent, _g): ev.set_data("amount", 5.0, "escudo"), 0, "escudo")
	var ev := eng.emit("t", "a", "b", {"amount": 100.0}, 0, CombatEvent.Phase.PRE)
	assert_almost(ev.data["amount"], 5.0, 1e-12, "el evento vivo refleja el cambio")
	# El registro conserva el valor original y aparece un EVENT_MODIFIED.
	assert_almost(eng.log.of_type("t")[0]["data"]["amount"], 100.0, 1e-12, "registro inmutable")
	var mods := eng.log.of_type(EventTypes.EVENT_MODIFIED)
	assert_eq(mods.size(), 1)
	assert_eq(mods[0]["data"]["by"] if mods[0]["data"].has("by") else mods[0]["source"], "escudo")
	assert_almost(mods[0]["data"]["old"], 100.0, 1e-12)
	assert_almost(mods[0]["data"]["new"], 5.0, 1e-12)
	assert_eq(mods[0]["cause"], ev.id)


func test_cancel_stops_lower_priority_interceptors_and_is_logged() -> void:
	var eng := _eng()
	var ran: Array = []
	eng.dispatcher.intercept("t", func(ev: CombatEvent, _g): ev.cancel("parada", "bloqueado"); ran.append(1), 0, "p")
	eng.dispatcher.intercept("t", func(_e, _g): ran.append(2), 1, "q")
	var ev := eng.emit("t", "a", "b", {}, 0, CombatEvent.Phase.PRE)
	assert_true(ev.cancelled)
	assert_eq(ran, [1])
	assert_eq(eng.log.of_type(EventTypes.EVENT_CANCELLED).size(), 1)


func test_info_events_cannot_be_cancelled_or_modified() -> void:
	var eng := _eng()
	var ev := eng.emit("t")
	ev.cancel("x")
	ev.set_data("a", 1, "x")
	assert_false(ev.cancelled)
	assert_false(ev.data.has("a"))


func test_observers_get_final_state_after_interception() -> void:
	var eng := _eng()
	var seen: Array = []
	eng.dispatcher.intercept("t", func(ev: CombatEvent, _g): ev.cancel("x"), 0, "i")
	eng.dispatcher.observe("t", func(ev: CombatEvent, _g): seen.append(ev.cancelled), 0, "o")
	eng.emit("t", "", "", {}, 0, CombatEvent.Phase.PRE)
	assert_eq(seen, [true])


func test_wildcard_and_unsubscribe_owner() -> void:
	var eng := _eng()
	var n := [0]
	eng.dispatcher.observe("*", func(_e, _g): n[0] += 1, 0, "w")
	var base: int = n[0]
	eng.emit("a1")
	eng.emit("a2")
	assert_eq(n[0] - base, 2)
	assert_true(eng.dispatcher.unsubscribe_owner("w") >= 1)
	eng.emit("a3")
	assert_eq(n[0] - base, 2)


func test_recursion_depth_limit_aborts_safely() -> void:
	var eng := make_engine([make_entity("a", "A"), make_entity("b", "B")], 1, {"safety": {"max_event_depth": 8}})
	eng.start()
	# Un observador que reemite sin fin: la profundidad se corta y el combate aborta.
	eng.dispatcher.observe("loop", func(_e, g: CombatEngine): g.emit("loop"), 0, "bad")
	eng.emit("loop")
	assert_true(eng.is_aborted())
	var r := eng.run()
	assert_true(r.is_aborted(), "aborto tecnico, no empate")
	assert_eq(r.error["code"], "max_event_depth")


func test_event_count_limit_aborts_safely() -> void:
	var eng := make_engine([make_entity("a", "A"), make_entity("b", "B")], 1, {"safety": {"max_events": 50}})
	var r := eng.run()
	# Con 50 eventos max el combate normal no cabe: debe abortar con diagnostico.
	assert_true(r.is_aborted())
	assert_eq(r.error["code"], "max_events")
	assert_ne(r.outcome, CombatResult.DRAW)
	assert_ne(r.outcome, CombatResult.WIN)


func test_log_hash_is_sensitive_to_content() -> void:
	var e1 := _eng()
	var e2 := _eng()
	e1.emit("x", "", "", {"v": 1})
	e2.emit("x", "", "", {"v": 2})
	assert_ne(e1.log.digest(), e2.log.digest())
