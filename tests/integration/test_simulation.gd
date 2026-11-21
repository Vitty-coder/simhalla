extends TestCase
## Fase 7: simulacion individual controlable, planificacion determinista de lotes, modalidades, ejecucion
## (sincrona/hilos), cancelacion, agregacion incremental y coherencia entre modos.

const FX := "res://content/fixtures/entities/"
const TMP := "user://_tests_phase7"
const FAST := {"ruleset_overrides": {"victory": {"limits": {"max_turns": 60, "stagnation_turns": 30}}}}


func _spec(name: String) -> Dictionary:
	return {"path": FX + name + ".json"}


func _duel_cfg(seed_value: int = 5) -> Dictionary:
	return {"seed": seed_value, "entities": [
		{"path": FX + "attacker_a.json", "overrides": {"id": "a", "team": "A"}},
		{"path": FX + "attacker_b.json", "overrides": {"id": "b", "team": "B"}}]}


func _plan(cfg: Dictionary) -> BatchPlan:
	var r := BatchPlan.from_dict(cfg)
	assert_eq(r["errors"], [], "plan")
	return r["plan"]


func _duel_batch(reps: int = 12, master: int = 7) -> Dictionary:
	return BatchModes.duel(_spec("attacker_a"), _spec("attacker_b"), reps, master, FAST, "A", "B")


func _run(p: BatchPlan, opts: Dictionary = {}) -> BatchResult:
	return BatchRunner.new(p, opts).wait()


# --- sesion individual ---------------------------------------------------------------------------------------

func test_session_controls_step_by_action_turn_and_to_end() -> void:
	var o := SimulationSession.open(_duel_cfg())
	assert_true(o["ok"], str(o["errors"]))
	var s: SimulationSession = o["session"]
	assert_eq(s.step_count, 0)
	s.step_action() # comienza el primer turno
	assert_eq(s.snapshot()["turn"], 1)
	assert_true(s.snapshot()["current_entity"] != "")
	s.step_turn()
	assert_true(s.engine.turn == null, "step_turn termina el turno en curso")
	var after_first: int = s.snapshot()["turn"]
	s.step_turn() # no hay turno: completa el siguiente entero
	assert_eq(s.snapshot()["turn"], after_first + 1)
	assert_true(s.engine.turn == null)
	# velocidad = pasos por llamada; la pausa detiene
	var steps := s.step_count
	assert_eq(s.advance(5), 5)
	assert_eq(s.step_count, steps + 5)
	s.pause()
	assert_eq(s.advance(5), 0, "en pausa no avanza")
	assert_eq(s.step_count, steps + 5)
	s.resume()
	assert_true(s.advance(2) == 2)
	var res := s.run_to_end()
	assert_true(s.is_finished())
	assert_true(res.is_win() or res.is_draw())
	assert_false(s.step_action(), "terminado: no hay mas pasos")
	# coherencia: sesion paso a paso == combate individual directo
	var direct := DuelRunner.run(_duel_cfg())["result"] as CombatResult
	assert_eq(res.log_hash, direct.log_hash, "la sesion usa el mismo motor")


func test_session_snapshot_forecast_incremental_events_and_causality() -> void:
	var s: SimulationSession = SimulationSession.open(_duel_cfg())["session"]
	s.advance(6)
	var snap := s.snapshot()
	assert_eq(snap["entities"].size(), 2)
	for e in snap["entities"]:
		assert_true(e.has("hp") and e.has("hp_max") and e.has("initiative") and e.has("resources") and e.has("statuses"))
	assert_eq(s.forecast(4).size(), 4)
	assert_true(float(s.forecast(1)[0]["time"]) >= float(snap["time"]))
	# lectura incremental: la concatenacion de lecturas es el registro completo, sin repetir
	var first := s.events_since_last()
	assert_true(first.size() > 0)
	assert_eq(s.events_since_last().size(), 0, "nada nuevo")
	s.run_to_end()
	var rest := s.events_since_last()
	assert_eq(first.size() + rest.size(), s.engine.log.events.size())
	# cadena causal hasta la raiz
	var dmg := s.engine.log.of_type(EventTypes.DAMAGE_DEALT)[0]
	var chain := s.causal_chain(int(dmg["id"]))
	assert_true(chain.size() >= 2)
	assert_eq(int(chain[0]["id"]), int(dmg["id"]))
	assert_eq(int(chain[chain.size() - 1]["cause"]), 0, "termina en un evento raiz")
	# una instantanea es una copia: mutarla no altera la partida
	var copy := s.snapshot()
	(copy["entities"][0] as Dictionary)["hp"] = -1.0
	assert_true(float(s.snapshot()["entities"][0]["hp"]) != -1.0)


func test_session_reconstructs_past_states_deterministically_without_touching_the_game() -> void:
	var s: SimulationSession = SimulationSession.open(_duel_cfg(9))["session"]
	var recorded := {}
	for k in 25:
		s.step_action()
		recorded[s.step_count] = s.snapshot()
	var final_hash_before := s.engine.log.count
	for k in [3, 10, 25]:
		var past := s.reconstruct_at(k)
		assert_eq(past.snapshot()["entities"], recorded[k]["entities"], "estado en el paso %d" % k)
		assert_almost(float(past.snapshot()["time"]), float(recorded[k]["time"]))
		assert_eq(past.snapshot()["turn"], recorded[k]["turn"])
	assert_eq(s.engine.log.count, final_hash_before, "inspeccionar el pasado no modifica la partida")
	assert_eq(s.step_count, 25)
	# continuar desde el pasado reconstruido llega al mismo final
	var past10 := s.reconstruct_at(10)
	var end_hash := past10.run_to_end().log_hash
	assert_eq(end_hash, s.run_to_end().log_hash)
	assert_eq(s.repeat_same_seed().run_to_end().log_hash, end_hash, "repetir con la misma semilla")
	assert_eq(s.reconstruct_at(0).snapshot()["time"], 0.0)


func test_session_cancel_is_not_a_defeat_and_initial_overrides_are_recorded() -> void:
	var s: SimulationSession = SimulationSession.open(_duel_cfg())["session"]
	s.advance(3)
	s.cancel()
	s.run_to_end()
	var r := s.result()
	assert_true(r.is_aborted())
	assert_eq(r.kind, "cancelled")
	assert_false(r.is_draw())
	var cfg := _duel_cfg()
	cfg["initial_overrides"] = {"a": {"hp": 100.0, "initiative": 50.0}}
	var s2: SimulationSession = SimulationSession.open(cfg)["session"]
	s2.step_action()
	var started := s2.engine.log.of_type(EventTypes.COMBAT_STARTED)
	assert_eq(started[0]["data"]["initial_overrides"]["a"]["hp"], 100.0, "la configuracion inicial alternativa queda registrada")
	assert_almost(float(s2.snapshot()["entities"][0]["hp"]), 100.0)
	var bad := SimulationSession.open({"seed": 1, "entities": [{"path": "res://nada.json"}]})
	assert_false(bad["ok"])
	assert_true(bad["session"] == null)


# --- planificacion --------------------------------------------------------------------------------------------

func test_seeds_are_derived_from_master_scenario_and_repetition_only() -> void:
	var p := _plan(_duel_batch(5, 11))
	assert_eq(p.job_count(), 5)
	var seeds := p.jobs.map(func(j): return j["seed"])
	assert_eq(seeds.size(), 5)
	assert_eq(_unique(seeds).size(), 5, "semillas distintas por repeticion")
	assert_eq(_plan(_duel_batch(5, 11)).jobs.map(func(j): return j["seed"]), seeds, "determinista")
	assert_ne(_plan(_duel_batch(5, 12)).jobs.map(func(j): return j["seed"]), seeds, "otra maestra, otras semillas")
	assert_eq(BatchPlan.derive_seed(11, "per_scenario", "a_vs_b", "", 2), seeds[2])
	# la semilla de un trabajo NO depende de su posicion en el plan ni del orden de escenarios
	var t := BatchModes.tournament([{"label": "x", "spec": _spec("attacker_a")}, {"label": "y", "spec": _spec("attacker_b")}, {"label": "z", "spec": _spec("slow_tank")}], 3, 4, FAST)
	var pa := _plan(t)
	var rev: Dictionary = t.duplicate(true)
	rev["scenarios"].reverse()
	var pb := _plan(rev)
	var map_a := {}
	for j in pa.jobs:
		map_a["%s#%d" % [pa.scenarios[j["scenario"]]["key"], j["repetition"]]] = j["seed"]
	for j in pb.jobs:
		assert_eq(map_a["%s#%d" % [pb.scenarios[j["scenario"]]["key"], j["repetition"]]], j["seed"], "mismo (escenario, repeticion) => misma semilla")
	assert_ne(pa.fingerprint(), pb.fingerprint(), "el orden del plan si es parte de la huella del plan")
	# modo emparejado: mismas semillas por repeticion en todas las variantes
	var c := BatchModes.compare_variants([{"label": "v1", "spec": _spec("attacker_a")}, {"label": "v2", "spec": _spec("glass_cannon")}], {"label": "o", "spec": _spec("attacker_b")}, 4, 5, FAST)
	var pc := _plan(c)
	assert_eq(pc.seed_mode, "paired")
	for r in 4:
		assert_eq(pc.jobs[r]["seed"], pc.jobs[4 + r]["seed"], "emparejado: la misma semilla")
	c["seed_mode"] = "per_scenario"
	var pd := _plan(c)
	assert_ne(pd.jobs[0]["seed"], pd.jobs[4]["seed"])


func _unique(a: Array) -> Dictionary:
	var d := {}
	for x in a:
		d[x] = true
	return d


func test_plan_validation_and_limits() -> void:
	var cases := {
		"propiedad": [{"schema": "simhalla.batch/1", "foo": 1, "scenarios": []}, "propiedad desconocida"],
		"schema": [{"schema": "otro/1", "scenarios": [{}]}, "schema debe ser"],
		"sin escenarios": [{"scenarios": []}, "no vacia"],
		"repeticiones": [{"repetitions": 0, "scenarios": [{"key": "k", "entities": [_spec("attacker_a"), _spec("attacker_b")]}]}, "repetitions"],
		"modo de semilla": [{"seed_mode": "azar", "scenarios": [{"key": "k", "entities": [_spec("attacker_a"), _spec("attacker_b")]}]}, "seed_mode"],
		"clave repetida": [{"scenarios": [{"key": "k", "entities": [_spec("attacker_a"), _spec("attacker_b")]}, {"key": "k", "entities": [_spec("attacker_a"), _spec("attacker_b")]}]}, "unica"],
		"una entidad": [{"scenarios": [{"key": "k", "entities": [_spec("attacker_a")]}]}, "al menos 2"],
		"entidad sin origen": [{"scenarios": [{"key": "k", "entities": [{"x": 1}, {"y": 2}]}]}, "'path', 'package' o 'data'"],
		"escenario con propiedad": [{"scenarios": [{"key": "k", "entities": [_spec("attacker_a"), _spec("attacker_b")], "oro": 1}]}, "propiedad desconocida"],
		"base": [{"base": {"magia": 1}, "scenarios": [{"key": "k", "entities": [_spec("attacker_a"), _spec("attacker_b")]}]}, "lote.base"],
		"demasiados trabajos": [{"repetitions": 2000000, "scenarios": [{"key": "k", "entities": [_spec("attacker_a"), _spec("attacker_b")]}]}, "superan el maximo"],
	}
	for k in cases:
		var r := BatchPlan.from_dict(cases[k][0])
		assert_true(r["plan"] == null and r["errors"].size() > 0, "debe rechazar: %s" % k)
		assert_contains(" ".join(r["errors"]), cases[k][1], k)
	# ida y vuelta del formato
	var p := _plan(_duel_batch())
	var again := BatchPlan.from_dict(JSON.parse_string(JSON.stringify(p.to_dict())))
	assert_eq(again["errors"], [])
	assert_eq((again["plan"] as BatchPlan).fingerprint(), p.fingerprint())


func test_modes_build_expected_scenarios() -> void:
	var a := {"label": "A", "spec": _spec("attacker_a")}
	var b := {"label": "B", "spec": _spec("attacker_b")}
	var c := {"label": "C", "spec": _spec("slow_tank")}
	assert_eq(_plan(BatchModes.tournament([a, b, c], 2, 1, FAST)).scenarios.size(), 6, "3 contendientes: 3 parejas x 2 lados")
	assert_eq(_plan(BatchModes.tournament([a, b, c], 2, 1, FAST, false)).scenarios.size(), 3)
	assert_eq(_plan(BatchModes.tournament([a, b, c], 2, 1, FAST)).job_count(), 12)
	var g := _plan(BatchModes.gauntlet(a, [b, c], 3, 1, FAST))
	assert_eq(g.scenarios.size(), 2)
	assert_eq(g.scenarios[0]["sides"], {"A": "A", "B": "B"})
	var ai := _plan(BatchModes.compare_ai(a, [{"label": "agr", "ai": {"type": "passive"}}, {"label": "def", "ai": {"type": "scored"}}], b, 3, 1, FAST))
	assert_eq(ai.scenarios.size(), 2)
	assert_eq(ai.scenarios[0]["entities"][0]["overrides"]["ai"], {"type": "passive"})
	assert_eq(ai.scenarios[1]["sides"]["A"], "A[def]")
	var rs := _plan(BatchModes.compare_rulesets(a, b, [{"label": "base", "overrides": {}}, {"label": "crit", "overrides": {"hit": {"max_chance": 0.5}}}], 3, 1, FAST))
	assert_eq(rs.scenarios.size(), 2)
	assert_eq(rs.scenarios[1]["ruleset_overrides"]["hit"]["max_chance"], 0.5)
	var sw := _plan(BatchModes.sweep(a, b, [{"path": "stats.ATK", "values": [100, 150, 200]}, {"path": "stats.SPD", "values": [90, 110]}], 0, 2, 1, FAST))
	assert_eq(sw.scenarios.size(), 6, "producto cartesiano 3 x 2")
	assert_eq(sw.scenarios[0]["params"], {"stats.ATK": 100, "stats.SPD": 90})
	assert_eq(sw.scenarios[0]["entities"][0]["patch"]["stats"]["ATK"], 100)
	var elem := _plan(BatchModes.sweep(a, b, [{"path": "stats.ELEM_AFF.fire", "values": [0.1]}], 0, 1, 1, FAST))
	assert_eq(elem.scenarios[0]["entities"][0]["patch"]["stats"]["ELEM_AFF.fire"], 0.1, "ids de estadistica con punto, enteros")
	var too_many := BatchPlan.from_dict(BatchModes.sweep(a, b, [{"path": "stats.ATK", "values": range(40)}, {"path": "stats.SPD", "values": range(40)}], 0, 1, 1, FAST, true, 100))
	assert_true(too_many["plan"] == null, "una rejilla enorme se rechaza")


# --- ejecucion y coherencia --------------------------------------------------------------------------------------

func test_results_do_not_depend_on_workers_order_or_trace_level() -> void:
	var p := _plan(_duel_batch(16, 21))
	var sync := _run(p, {"workers": 0})
	var one := _run(p, {"workers": 1})
	var three := _run(p, {"workers": 3})
	assert_true(sync.is_complete() and one.is_complete() and three.is_complete())
	assert_eq(sync.executed, 16)
	assert_eq(one.fingerprint, sync.fingerprint, "1 worker == sincrono")
	assert_eq(three.fingerprint, sync.fingerprint, "3 workers == sincrono")
	for i in 16:
		assert_eq(three.records[i]["log_hash"], sync.records[i]["log_hash"], "trabajo %d" % i)
		assert_eq(three.records[i]["index"], i)
	assert_eq(JSON.stringify(three.summary), JSON.stringify(sync.summary), "el resumen agregado tampoco depende de los workers")
	# traza reducida vs completa: mismo resultado
	var full := _run(p, {"workers": 0, "keep_traces": true})
	assert_eq(full.fingerprint, sync.fingerprint, "la traza no cambia el resultado")
	assert_true((full.records[0] as Dictionary).has("events_log"))
	assert_false((sync.records[0] as Dictionary).has("events_log"), "por defecto no se guardan trazas")
	# orden de escenarios invertido: cada escenario da exactamente lo mismo
	var t := BatchModes.tournament([{"label": "x", "spec": _spec("attacker_a")}, {"label": "y", "spec": _spec("attacker_b")}, {"label": "z", "spec": _spec("slow_tank")}], 4, 3, FAST)
	var rev: Dictionary = t.duplicate(true)
	rev["scenarios"].reverse()
	var r1 := _run(_plan(t), {"workers": 2})
	var r2 := _run(_plan(rev), {"workers": 0})
	var by_key := func(res: BatchResult) -> Dictionary:
		var d := {}
		for s in res.summary["scenarios"]:
			d[s["key"]] = JSON.stringify(s)
		return d
	assert_eq(by_key.call(r1), by_key.call(r2), "el resultado de cada escenario no depende del orden del plan")


func test_batch_jobs_match_standalone_duels_and_are_replayable() -> void:
	var p := _plan(_duel_batch(6, 33))
	var res := _run(p, {"workers": 2})
	for rec in res.records:
		var direct := DuelRunner.run(p.job_config(int(rec["index"]), "reduced"))
		assert_true(direct["ok"])
		assert_eq((direct["result"] as CombatResult).log_hash, rec["log_hash"], "lote == combate individual (semilla %d)" % int(rec["seed"]))
		assert_true(BatchRunner.verify(p, rec))
	var rep := BatchRunner.replay(p, 2)
	assert_true(rep["ok"])
	assert_eq((rep["result"] as CombatResult).log_hash, res.records[2]["log_hash"])
	assert_true((rep["engine"] as CombatEngine).log.events.size() > 0, "la reproduccion tiene traza completa")
	var tampered: Dictionary = (res.records[2] as Dictionary).duplicate()
	tampered["log_hash"] = "0".repeat(64)
	assert_false(BatchRunner.verify(p, tampered), "un registro alterado no verifica")
	# la configuracion queda registrada: version del motor, huella del plan
	assert_eq(res.engine_version, CombatEngine.ENGINE_VERSION)
	assert_eq(res.plan_fingerprint, p.fingerprint())


func test_incremental_aggregation_progress_and_cooperative_slices() -> void:
	var p := _plan(_duel_batch(10, 5))
	var seen: Array = []
	var r := BatchRunner.new(p, {"workers": 0, "on_progress": func(pr: Dictionary): seen.append(pr["done"])})
	var pr := r.run_slice(3)
	assert_eq(pr["done"], 3)
	assert_eq(pr["pending"], 7)
	assert_eq(r.accumulator.totals["jobs"], 3, "agregacion incremental")
	pr = r.run_slice(100, 1) # limite de tiempo: devuelve el control pronto
	assert_true(pr["done"] < 10 or pr["done"] == 10)
	var res := r.wait()
	assert_eq(res.executed, 10)
	assert_true(seen.size() >= 2 and seen[0] == 3, "on_progress se invoca desde el hilo principal")
	assert_eq(r.accumulator.totals["jobs"], 10)
	assert_eq(JSON.stringify(BatchAccumulator.rebuild(res.records).summary()), JSON.stringify(res.summary), "el acumulado incremental == reconstruido en orden")
	# hilos: poll agrega mientras corre
	var rt := BatchRunner.new(p, {"workers": 2})
	rt.start()
	var polls := 0
	while not rt.is_finished():
		rt.poll()
		polls += 1
		OS.delay_msec(2)
	var res2 := rt.wait()
	assert_eq(rt.accumulator.totals["jobs"], 10)
	assert_eq(res2.fingerprint, res.fingerprint)


func test_summary_has_explicit_denominators_and_separates_errors() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var path := TMP + "/boom.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"id": "boom", "name": "Boom", "stats": {"SPD": 200}, "basic_attack": false, "scripts": {"s": "fn run(ctx) { let x = 1 / 0; }"},
		"abilities": [{"id": "zap", "targeting": "enemy", "effects": [{"type": "script", "script": "s"}]}], "ai": {"type": "priority_list", "rules": [{"ability": "zap"}]}}))
	f.close()
	var cfg := {"schema": "simhalla.batch/1", "name": "mix", "master_seed": 3, "repetitions": 6, "base": FAST, "scenarios": [
		{"key": "ok", "entities": [{"path": FX + "attacker_a.json", "overrides": {"team": "A"}}, {"path": FX + "attacker_b.json", "overrides": {"team": "B"}}], "sides": {"A": "A", "B": "B"}},
		{"key": "aborta", "entities": [{"path": path, "overrides": {"team": "A"}}, {"path": FX + "attacker_b.json", "overrides": {"team": "B"}}], "sides": {"A": "Boom", "B": "B"}},
		{"key": "no_existe", "entities": [{"path": TMP + "/nada.json", "overrides": {"team": "A"}}, {"path": FX + "attacker_b.json", "overrides": {"team": "B"}}], "sides": {"A": "X", "B": "B"}},
		{"key": "empate", "entities": [{"path": FX + "passive_waiter.json", "overrides": {"id": "p1", "team": "A"}}, {"path": FX + "passive_waiter.json", "overrides": {"id": "p2", "team": "B"}}], "sides": {"A": "P1", "B": "P2"}},
	]}
	var res := _run(_plan(cfg), {"workers": 2})
	var t: Dictionary = res.summary["totals"]
	assert_eq(t["jobs"], 24)
	assert_eq(t["aborted"], 6, "los abortos tecnicos se cuentan aparte")
	assert_eq(t["setup_errors"], 6)
	assert_eq(t["finished"], 12)
	assert_eq(t["wins"] + t["draws"], t["finished"])
	var by_key := {}
	for s in res.summary["scenarios"]:
		by_key[s["key"]] = s
	assert_eq(by_key["ok"]["denominator"], 6)
	assert_eq(by_key["aborta"]["n_finished"], 0, "un aborto NO es derrota ni empate")
	assert_eq(by_key["aborta"]["n_errors"], 6)
	assert_eq(by_key["aborta"]["wins_by_label"], {})
	assert_contains(by_key["aborta"]["errors"][0], "script_error")
	assert_eq(by_key["no_existe"]["setup_errors"], 6)
	assert_eq(by_key["empate"]["draws"], 6)
	assert_almost(by_key["empate"]["draw_rate"], 1.0)
	var ok_total: int = 0
	for w in by_key["ok"]["wins_by_label"].values():
		ok_total += int(w)
	assert_eq(ok_total + by_key["ok"]["draws"], by_key["ok"]["n_finished"])
	var bl: Dictionary = res.summary["by_label"]
	assert_eq(bl["A"]["games"], bl["A"]["wins"] + bl["A"]["losses"] + bl["A"]["draws"], "denominador por etiqueta")
	assert_false(bl.has("Boom"), "los abortos no suman partidas")
	assert_true(by_key["ok"]["turns"]["n"] == 6 and by_key["ok"]["turns"]["mean"] > 0.0)
	assert_true(float(by_key["ok"]["damage_mean_by_label"]["A"]) > 0.0)
	ContentLibrary._remove_tree(TMP)


# --- cancelacion ---------------------------------------------------------------------------------------------------

func test_cancel_keeps_finished_results_valid_and_never_counts_as_defeat() -> void:
	var p := _plan(_duel_batch(300, 17))
	var full_first := {}
	for i in 6:
		full_first[i] = (DuelRunner.run(p.job_config(i, "reduced"))["result"] as CombatResult).log_hash
	var r := BatchRunner.new(p, {"workers": 2})
	r.start()
	var guard := 0
	while r.progress()["done"] < 8 and guard < 5000:
		OS.delay_msec(2)
		guard += 1
	r.cancel()
	var res := r.wait()
	assert_eq(res.status, "cancelled")
	assert_true(res.executed >= 8 and res.executed < 300, "parcial: %d" % res.executed)
	assert_eq(res.pending(), 300 - res.executed)
	var t: Dictionary = res.summary["totals"]
	assert_eq(t["finished"] + t["aborted"] + t["setup_errors"] + t["cancelled"], res.executed)
	assert_eq(t["aborted"], 0, "cancelar no es un error tecnico")
	assert_eq(t["finished"], t["wins"] + t["draws"], "los cancelados no cuentan como victoria/derrota/empate")
	for rec in res.records:
		if rec != null and rec["status"] != "cancelled":
			assert_true(rec["status"] in ["win", "draw"])
	for i in 6:
		if res.records[i] != null and res.records[i]["status"] != "cancelled":
			assert_eq(res.records[i]["log_hash"], full_first[i], "lo terminado es reproducible (trabajo %d)" % i)
	assert_ne(res.fingerprint, _run(_plan(_duel_batch(4, 17)), {}).fingerprint)
	# cancelacion cooperativa (sin hilos)
	var rs := BatchRunner.new(_plan(_duel_batch(50, 17)), {"workers": 0})
	rs.run_slice(4)
	rs.cancel()
	var res2 := rs.wait()
	assert_eq(res2.executed, 4)
	assert_eq(res2.status, "cancelled")
	assert_true(rs.is_cancelled())


func test_cancelled_running_combat_is_recorded_as_cancelled() -> void:
	var p := _plan(BatchModes.duel(_spec("passive_waiter"), _spec("passive_waiter"), 3, 1, {"ruleset_overrides": {"victory": {"limits": {"max_turns": 100000, "stagnation_turns": 100000, "max_actions": 100000, "max_virtual_time": 10000000.0}}}}))
	var r := BatchRunner.new(p, {"workers": 1})
	r.start()
	OS.delay_msec(60)
	r.cancel()
	var res := r.wait()
	assert_true(res.executed >= 1)
	var cancelled := res.records.filter(func(x): return x != null and x["status"] == "cancelled")
	assert_true(cancelled.size() >= 1, "el combate en curso se aborta como cancelado")
	assert_eq(res.summary["totals"]["aborted"], 0)
	assert_eq(res.summary["totals"]["finished"], res.executed - cancelled.size())


# --- modalidades de extremo a extremo ---------------------------------------------------------------------------------

func test_tournament_gauntlet_and_sweep_run_end_to_end() -> void:
	var cs := [{"label": "a", "spec": _spec("attacker_a")}, {"label": "b", "spec": _spec("attacker_b")}, {"label": "t", "spec": _spec("slow_tank")}]
	var tr := _run(_plan(BatchModes.tournament(cs, 6, 2, FAST)), {"workers": 2})
	assert_eq(tr.executed, 36)
	assert_eq(tr.summary["totals"]["aborted"] + tr.summary["totals"]["setup_errors"], 0)
	var bl: Dictionary = tr.summary["by_label"]
	assert_eq(bl.keys().size(), 3)
	for l in bl:
		assert_eq(bl[l]["games"], 24, "cada contendiente juega 2 parejas x 2 lados x 6")
		assert_eq(bl[l]["games"], bl[l]["wins"] + bl[l]["losses"] + bl[l]["draws"])
	var gn := _run(_plan(BatchModes.gauntlet(cs[0], [cs[1], cs[2]], 5, 2, FAST)), {"workers": 0})
	assert_eq(gn.summary["scenarios"].size(), 2)
	# variacion controlada: mas ATK de A no puede empeorar su tasa de victoria (semillas emparejadas)
	var sw := _run(_plan(BatchModes.sweep(cs[0], cs[1], [{"path": "stats.ATK", "values": [60, 150, 400]}], 0, 24, 9, FAST)), {"workers": 2})
	var rates: Array = []
	for s in sw.summary["scenarios"]:
		rates.append(float(s["win_rates"].get("a", 0.0)))
	assert_eq(rates.size(), 3)
	var by_atk := {}
	for rec in sw.records:
		var atk: int = int(rec["params"]["stats.ATK"])
		by_atk[atk] = int(by_atk.get(atk, 0)) + (1 if rec["status"] == "win" and rec["winner_team"] == "A" else 0)
	assert_true(by_atk[400] >= by_atk[150] and by_atk[150] >= by_atk[60], "monotonia con semillas emparejadas: %s" % str(by_atk))
	# comparar reglamentos y perfiles de IA
	var rc := _run(_plan(BatchModes.compare_rulesets(cs[0], cs[1], [{"label": "base", "overrides": {}}, {"label": "ciego", "overrides": {"hit": {"min_chance": 0.01, "max_chance": 0.05}}}], 8, 4, FAST)), {"workers": 2})
	var by_rule := {}
	for s in rc.summary["scenarios"]:
		by_rule[s["key"]] = s
	assert_true(float(by_rule["ruleset__ciego"]["turns"]["mean"]) > float(by_rule["ruleset__base"]["turns"]["mean"]), "un reglamento con casi todo fallos alarga los combates")
	var ac := _run(_plan(BatchModes.compare_ai(cs[0], [{"label": "pasiva", "ai": {"type": "passive"}}, {"label": "activa", "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack"}]}}], cs[1], 6, 4, FAST)), {"workers": 0})
	var win_active := 0.0
	var win_passive := 0.0
	for s in ac.summary["scenarios"]:
		var l: Dictionary = s["win_rates"]
		if s["key"] == "variant__a[activa]":
			win_active = float(l.get("a[activa]", 0.0))
		else:
			win_passive = float(l.get("a[pasiva]", 0.0))
	assert_true(win_active > win_passive, "la IA activa gana mas que la pasiva")


func test_package_versions_comparison_records_content_hashes() -> void:
	var lib := ContentLibrary.new("%s/lib%d" % [TMP, Time.get_ticks_usec()])
	var imp := PackageImporter.new(lib)
	for v in [["1.0.0", 100], ["1.1.0", 300]]:
		var d := "%s/hero_%s" % [TMP, v[0]]
		DirAccess.make_dir_recursive_absolute(d)
		for rel in {"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": "t/hero", "version": v[0], "type": "character", "name": "H"}),
				"character.json": JSON.stringify({"schema": "simhalla.character/1", "name": "Hero", "stats": {"ATK": v[1]}, "basic_attack": true})}:
			var f := FileAccess.open(d.path_join(rel), FileAccess.WRITE)
			f.store_string({"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": "t/hero", "version": v[0], "type": "character", "name": "H"}),
				"character.json": JSON.stringify({"schema": "simhalla.character/1", "name": "Hero", "stats": {"ATK": v[1]}, "basic_attack": true})}[rel])
			f.close()
		assert_true(imp.import_package(d).ok())
	var base := FAST.duplicate(true)
	base["library"] = lib.root
	var cfg := BatchModes.compare_variants([{"label": "v1.0.0", "spec": {"package": "t/hero", "version": "1.0.0"}}, {"label": "v1.1.0", "spec": {"package": "t/hero", "version": "1.1.0"}}],
		{"label": "b", "spec": _spec("attacker_b")}, 10, 3, base)
	var res := _run(_plan(cfg), {"workers": 2})
	assert_eq(res.summary["totals"]["setup_errors"], 0, str(res.summary))
	assert_eq(res.contents.keys().size(), 2)
	var h1: String = res.contents["variant__v1.0.0"][0]["content"]["hash"]
	var h2: String = res.contents["variant__v1.1.0"][0]["content"]["hash"]
	assert_eq(h1.length(), 64)
	assert_ne(h1, h2, "se registran las huellas de las versiones comparadas")
	ContentLibrary._remove_tree(TMP)


func test_performance_is_measured_but_never_part_of_the_fingerprint() -> void:
	var p := _plan(_duel_batch(10, 2))
	var a := _run(p, {"workers": 0})
	var b := _run(p, {"workers": 2})
	assert_true(a.perf["jobs_per_s"] > 0.0 and a.perf["events_per_s"] > 0.0)
	assert_eq(b.perf["workers"], 2)
	assert_eq(a.fingerprint, b.fingerprint)
	var d := a.to_dict()
	assert_true(d.has("perf") and d.has("records") and d.has("summary") and d.has("fingerprint"))
	assert_eq(JSON.parse_string(JSON.stringify(d))["fingerprint"], a.fingerprint, "exportable a JSON")
	assert_false(a.to_dict(false).has("records"))


func test_scripted_and_summoning_content_runs_deterministically_in_threads() -> void:
	var lib := ContentLibrary.new("%s/lib%d" % [TMP, Time.get_ticks_usec()])
	assert_true(PackageImporter.new(lib).import_package("res://content/packages/rune_caster").ok())
	var base := FAST.duplicate(true)
	base["library"] = lib.root
	var cfg := BatchModes.gauntlet({"label": "rune", "spec": {"package": "examples/rune_caster"}},
		[{"label": "b", "spec": _spec("attacker_b")}, {"label": "tank", "spec": _spec("slow_tank")}], 10, 12, base)
	var p := _plan(cfg)
	var sync := _run(p, {"workers": 0})
	var par := _run(p, {"workers": 3})
	assert_eq(sync.summary["totals"]["aborted"], 0, str(sync.summary["scenarios"]))
	assert_eq(par.fingerprint, sync.fingerprint, "scripts + IA programada: mismo resultado con hilos")
	ContentLibrary._remove_tree(TMP)


func test_batch_plan_files_match_the_public_schema() -> void:
	var v := SchemaValidator.new()
	var demo: Dictionary = EntityFactory.load_json("res://content/batches/demo_duel.json")
	assert_eq(v.validate("batch.schema.json", demo), [])
	assert_eq(BatchPlan.from_dict(demo)["errors"], [])
	assert_eq(v.validate("batch.schema.json", _duel_batch()), [], "los constructores producen el formato publico")
	assert_true(v.validate("batch.schema.json", {"scenarios": [{"key": "k", "entities": [_spec("attacker_a")]}]}).size() > 0)
	assert_true(v.validate("batch.schema.json", {"seed_mode": "azar", "scenarios": []}).size() > 0)
