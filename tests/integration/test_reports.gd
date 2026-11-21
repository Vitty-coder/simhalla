extends Phase3Case
## Fase 8: informes individual y masivo (modelo versionado), exportadores JSON/Markdown/HTML, consistencia y
## reproducibilidad, seguridad de escape y modo de depuracion.

const FX := "res://content/fixtures/entities/"
const TMP := "user://_tests_phase8"
const FAST := {"ruleset_overrides": {"victory": {"limits": {"max_turns": 60, "stagnation_turns": 30}}}}


func _cfg(seed_value: int = 5, a: String = "glass_cannon", b: String = "slow_tank") -> Dictionary:
	return {"seed": seed_value, "entities": [
		{"path": FX + a + ".json", "overrides": {"id": "a", "team": "A"}},
		{"path": FX + b + ".json", "overrides": {"id": "b", "team": "B"}}]}


func _session(cfg: Dictionary) -> SimulationSession:
	var o := SimulationSession.open(cfg)
	assert_true(o["ok"], str(o["errors"]))
	var s: SimulationSession = o["session"]
	s.run_to_end()
	return s


func _report(cfg: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var s := _session(cfg)
	var o := opts.duplicate()
	o["config"] = cfg
	var r := IndividualReport.build(s.engine, o)
	assert_true(r["ok"], str(r["errors"]))
	return r["report"]


func _rich_engine() -> CombatEngine:
	# escudo, veneno, recursos, critico, reaccion, esquivas: cubre todas las secciones
	var counter := dmg_ability("counter", "7", {"action_type": "reaction", "trigger": {"event": "damage_dealt", "when": {"event.target": {"eq": "self"}}, "target": "event_source", "chance": 0.5}})
	var a := ent("a", "A", {"stats": {"SPD": 120, "HP": 900, "ACC": 0.9, "CRIT": 0.3}, "resources": {"mana": {"initial": 60, "max": 60, "regen_per_turn": 5}}, "basic_attack": true,
		"abilities": [{"id": "venom", "targeting": "enemy", "cost": {"mana": 20}, "cooldown": 2, "effects": [{"type": "apply_status", "status": "poison", "stacks": 2, "duration": 3},
			{"type": "damage", "components": [{"damage_type": "physical", "formula": "caster.ATK"}]}]},
			{"id": "mend", "targeting": "self", "effects": [{"type": "heal", "formula": "300"}]}],
		"ai": {"type": "scored", "weights": {"damage": 1, "status": 0.5, "heal": 1, "need": 2}}})
	var b := ent("b", "B", {"stats": {"SPD": 100, "HP": 900, "EVA": 0.2}, "basic_attack": true, "abilities": [counter, {"id": "raise", "targeting": "self", "effects": [{"type": "apply_status", "status": "ward"}]}],
		"statuses": [{"id": "ward", "duration": {"unit": "permanent"}, "beneficial": true, "defense": {"absorb": {"amount": "60"}}}],
		"ai": {"type": "priority_list", "rules": [{"ability": "raise", "target": "self", "when": {"self.status.ward": {"lt": 1}}}, {"ability": "basic_attack", "target": "first_enemy"}]}})
	var eng := engine([a, b], 4, {"victory": {"limits": {"max_turns": 25, "stagnation_turns": 99}}})
	eng.run()
	return eng


# --- individual ---------------------------------------------------------------------------------------------------

func test_individual_report_has_all_sections_and_consistent_figures() -> void:
	var cfg := _cfg()
	var s := _session(cfg)
	var m: Dictionary = IndividualReport.build(s.engine, {"config": cfg})["report"]
	assert_eq(m["schema"], "simhalla.report/1")
	assert_eq(m["kind"], "individual")
	for sec in ["meta", "result", "duration", "damage", "healing", "attacks", "abilities", "resources", "statuses", "defenses", "ai", "randomness", "metrics", "history", "reproduce"]:
		assert_true(m.has(sec), "seccion %s" % sec)
	assert_eq(IndividualReport.verify_invariants(m), [], "los datos cuadran entre si")
	assert_eq(ReportVerifier.check_individual(m), [])
	var r := s.result()
	assert_eq(m["meta"]["log_hash"], r.log_hash)
	assert_eq(m["meta"]["engine_version"], CombatEngine.ENGINE_VERSION)
	assert_eq(m["meta"]["seed"], "5", "las semillas van como texto (64 bits)")
	assert_eq(m["meta"]["entities"].size(), 2)
	assert_eq(m["result"]["outcome"], r.outcome)
	assert_eq(m["duration"]["turns_global"], r.turns)
	assert_eq(m["duration"]["events"], r.events)
	assert_almost(m["duration"]["virtual_time"], r.end_time)
	# cruce con las estadisticas del propio motor (observador CombatStats): el informe, calculado del registro, coincide
	for id in ["a", "b"]:
		var st: Dictionary = r.stats[id]
		var dm: Dictionary = m["damage"]["by_entity"][id]
		assert_almost(dm["dealt"], st["damage_dealt"], 1e-6, "dano causado de %s" % id)
		assert_almost(dm["taken"], st["damage_taken"], 1e-6)
		assert_almost(dm["intended"], st["damage_intended"], 1e-6)
		assert_almost(dm["premitigation"], st["damage_premitigation"], 1e-6)
		assert_almost(dm["mitigated"], st["damage_mitigated"], 1e-6)
		assert_almost(dm["overkill"], st["overkill"], 1e-6)
		assert_eq(m["attacks"]["by_entity"][id]["hits"], st["hits"])
		assert_eq(m["attacks"]["by_entity"][id]["misses"], st["misses"])
		assert_eq(m["duration"]["turns_by_entity"].get(id, 0), st["turns"])
		for ab in st["abilities"]:
			assert_eq(m["abilities"]["by_entity"][id][ab]["uses"], st["abilities"][ab]["uses"], "usos de %s/%s" % [id, ab])
			assert_almost(m["abilities"]["by_entity"][id][ab]["damage_effective"], st["abilities"][ab]["damage_dealt"], 1e-6, "atribucion por habilidad")
	# dano intentado, premitigacion, efectivo y sobreexceso separados (sin doble conteo)
	var a: Dictionary = m["damage"]["by_entity"]["a"]
	assert_true(a["premitigation"] >= a["dealt"] and a["intended"] > 0.0 and a["mitigated"] >= 0.0)
	assert_contains(m["damage"]["note"], "no contar dos veces")


func test_individual_report_covers_statuses_defenses_resources_ai_randomness() -> void:
	var eng := _rich_engine()
	var m: Dictionary = IndividualReport.build(eng, {})["report"]
	assert_eq(IndividualReport.verify_invariants(m), [])
	assert_true(m["statuses"]["by_entity"]["b"].has("poison"), "veneno aplicado por a")
	assert_true(m["statuses"]["by_entity"]["b"]["poison"]["applications"] >= 1)
	assert_true(m["statuses"]["by_entity"]["b"]["ward"]["applications"] >= 1)
	assert_true(m["damage"]["absorbed_total"] > 0.0, "el escudo absorbe")
	assert_true(m["damage"]["absorbed_by"].size() >= 1)
	assert_true(m["defenses"]["mitigation_by_source"].size() >= 1)
	assert_true(m["resources"]["by_entity"]["a"]["mana"]["consumed"] > 0.0)
	assert_true(m["resources"]["by_entity"]["a"]["mana"]["generated"] > 0.0, "regeneracion por turno")
	assert_eq(m["abilities"]["by_entity"]["a"]["venom"]["resources_spent"]["mana"], 20.0 * m["abilities"]["by_entity"]["a"]["venom"]["uses"])
	assert_true(m["healing"]["by_entity"].has("a") or m["abilities"]["by_entity"]["a"].has("mend") == false)
	assert_true(m["ai"]["by_entity"]["a"]["decisions"] > 0)
	assert_true(m["ai"]["by_entity"]["a"]["candidates_mean"] != null, "IA puntuada: candidatos medios")
	assert_true(m["ai"]["by_entity"]["b"]["reasons"].size() >= 1)
	assert_true(m["randomness"]["hit"]["rolls"] > 0 and m["randomness"]["hit"]["mean_chance"] != null)
	assert_true(m["randomness"]["proc"].has("trigger:counter"), "tiradas de proc de la reaccion")
	assert_true(m["attacks"]["by_entity"]["a"]["crits"] >= 0)
	# la atribucion causal asigna el dano de la reaccion a la habilidad de la reaccion
	var b_src: Dictionary = m["damage"]["by_source_ability"].get("b", {})
	assert_true(b_src.has("basic_attack") or b_src.has("counter"))


func test_individual_report_is_deterministic_and_reproducible() -> void:
	var cfg := _cfg(8)
	var m1 := _report(cfg)
	var m2 := _report(cfg)
	assert_eq(ReportExporter.to_json(m1), ReportExporter.to_json(m2), "mismo combate, mismo informe byte a byte")
	assert_eq(ReportExporter.content_hash(m1), ReportExporter.content_hash(m2))
	assert_ne(ReportExporter.content_hash(m1), ReportExporter.content_hash(_report(_cfg(9))), "otra semilla, otro informe")
	var rep := ReportVerifier.reproduce_individual(m1)
	assert_true(rep["ok"], str(rep["errors"]))
	# informe alterado o log_hash falso: se detecta
	var bad: Dictionary = JSON.parse_string(ReportExporter.to_json(m1))
	bad["reproduce"]["log_hash"] = "0".repeat(64)
	assert_false(ReportVerifier.reproduce_individual(bad)["ok"])
	var bad2: Dictionary = JSON.parse_string(ReportExporter.to_json(m1))
	bad2["damage"]["by_entity"]["a"]["dealt"] = 1.0
	assert_false(ReportVerifier.reproduce_individual(bad2)["ok"], "cifras alteradas no se reproducen")
	assert_true(ReportVerifier.check_individual(bad2).size() > 0, "la coherencia interna detecta la alteracion")
	assert_false(ReportVerifier.reproduce_individual({"reproduce": {}})["ok"])
	# no hay marcas de tiempo: nada que dependa del reloj
	var text := ReportExporter.to_json(m1)
	for w in ["timestamp", "generated_at", "created_at", "date"]:
		assert_false(text.contains("\"%s\"" % w), w)


func test_history_modes_and_causal_links() -> void:
	var cfg := _cfg()
	var none := _report(cfg, {"history": "none"})
	assert_false(none.has("history"))
	var summary := _report(cfg, {"history": "summary", "history_limit": 30})
	assert_eq(summary["history"]["events"].size(), 30)
	assert_true(summary["history"]["truncated"])
	var full := _report(cfg, {"history": "full"})
	assert_eq(full["history"]["events"].size(), full["duration"]["events"])
	assert_false(full["history"]["truncated"])
	var ids := {}
	for e in full["history"]["events"]:
		ids[int(e["id"])] = true
		assert_true(int(e["cause"]) == 0 or ids.has(int(e["cause"])), "relacion causal valida")
	# el informe individual exige traza completa
	var built := DuelRunner.build_engine({"seed": 1, "trace": "reduced", "entities": _cfg()["entities"]})
	var eng: CombatEngine = built["engine"]
	eng.run()
	var r := IndividualReport.build(eng, {})
	assert_false(r["ok"])
	assert_contains(" ".join(r["errors"]), "traza completa")


func test_individual_report_includes_balance_section_and_metrics() -> void:
	var data: Dictionary = EntityFactory.load_json(FX + "glass_cannon.json")
	var prof := BalanceProfile.from_file("res://content/balance/reference_costs.json")
	var br := BalanceEvaluator.evaluate(data, prof, Ruleset.from_dict({}), OperationRegistry.new(), {"mode": "regulated", "budget": "small"})
	var m := _report(_cfg(), {"balance": br.to_dict()})
	var b: Dictionary = m["balance"]
	assert_eq(b["profile"]["id"], "reference_costs")
	assert_true(b["labels"].size() == 1, "etiqueta de PRUEBA")
	assert_almost(b["creation_cost"], br.creation_cost)
	assert_true(b["top_components"].size() > 0)
	assert_true(b["items"].size() > 0)
	assert_contains(ReportExporter.to_markdown(m), "Equilibrio")
	var over := _report(_cfg(), {"balance": BalanceEvaluator.evaluate({"id": "x", "team": "A", "stats": {"ATK": 5000}}, prof, Ruleset.from_dict({}), OperationRegistry.new(), {"mode": "free", "budget": "small"}).to_dict()})
	assert_true(over["balance"]["discrepancies"].size() > 0, "discrepancias (presupuesto) visibles")
	# metricas de contenido
	var src := "fn run(ctx) { metric(\"golpes_script\", 3); metric(\"golpes_script\", 4); }"
	var a := ent("a", "A", {"stats": {"SPD": 100}, "scripts": {"s": src}, "abilities": [{"id": "z", "targeting": "enemy", "effects": [{"type": "script", "script": "s"}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "z"}]}})
	var eng := engine([a, ent("t", "B", {"stats": {"SPD": 1, "HP": 9000}})], 1, {"victory": {"limits": {"max_turns": 3, "stagnation_turns": 99}}})
	eng.run()
	var mm: Dictionary = IndividualReport.build(eng, {})["report"]
	assert_eq(mm["metrics"].size(), 1)
	assert_eq(mm["metrics"][0]["name"], "golpes_script")
	assert_almost(mm["metrics"][0]["total"], 21.0)
	assert_eq(mm["metrics"][0]["count"], 6)
	assert_eq(mm["metrics"][0]["aggregation"], "suma por combate; media por lote")


# --- masivo -------------------------------------------------------------------------------------------------------------

func _batch(cfg: Dictionary, workers: int = 0) -> BatchResult:
	var r := BatchPlan.from_dict(cfg)
	assert_eq(r["errors"], [])
	return BatchRunner.new(r["plan"], {"workers": workers}).wait()


func _tournament(reps: int = 6) -> Dictionary:
	var cs := [{"label": "a", "spec": {"path": FX + "attacker_a.json"}}, {"label": "b", "spec": {"path": FX + "attacker_b.json"}}, {"label": "t", "spec": {"path": FX + "slow_tank.json"}}]
	return BatchModes.tournament(cs, reps, 5, FAST)


func test_batch_report_statistics_are_correct_and_consistent() -> void:
	var res := _batch(_tournament(10))
	var m := BatchReport.build(res)
	assert_eq(m["kind"], "batch")
	assert_eq(ReportVerifier.check_batch(m), [], "coherencia interna")
	assert_eq(ReportVerifier.verify_batch(m, res), [], "recalculable desde los registros")
	assert_eq(m["meta"]["fingerprint"], res.fingerprint)
	assert_eq(m["meta"]["plan_fingerprint"], res.plan_fingerprint)
	assert_eq(m["sample"]["total_jobs"], 60)
	assert_eq(m["sample"]["finished"], 60)
	assert_eq(m["scenarios"].size(), 6)
	for s in m["scenarios"]:
		assert_eq(s["sample"]["denominator"], 10)
		var k := 0
		for l in s["outcomes"]["wins"]:
			var w: Dictionary = s["outcomes"]["wins"][l]
			k += w["k"]
			assert_almost(w["rate"], float(w["k"]) / 10.0)
			var iv: Array = Stats.wilson(w["k"], 10)
			assert_almost(w["wilson95"][0], iv[0], 1e-12)
			assert_almost(w["wilson95"][1], iv[1], 1e-12)
		assert_eq(k + s["outcomes"]["draws"]["k"], 10)
		assert_eq(s["distributions"]["turns"]["n"], 10)
		assert_true(s["distributions"]["turns"]["ci95"] != null)
		assert_true(s["distributions"]["turns"]["histogram"].size() > 0)
		assert_true(s["distributions"]["turns"]["min"] <= s["distributions"]["turns"]["median"] and s["distributions"]["turns"]["median"] <= s["distributions"]["turns"]["max"])
		assert_true(s["jobs"].size() >= 1, "semillas para reproducir")
	# clasificacion y matriz de favorables/desfavorables
	assert_eq(m["ranking"].size(), 3)
	var games := 0
	for e in m["ranking"]:
		games += e["games"]
		assert_eq(e["wins"] + e["losses"] + e["draws"], e["games"])
	assert_eq(games, 120, "cada partida cuenta para sus dos contendientes")
	assert_eq(m["matrix"]["cells"].size(), 6)
	for c in m["matrix"]["cells"]:
		assert_eq(c["games"], 20, "ambos lados")
	assert_true(m["methods"].has("rates") and m["methods"].has("abilities") and m["methods"].has("caveat"))
	assert_contains(m["methods"]["abilities"], "no demuestra")
	# asociacion habilidad-victoria con denominadores
	var ab: Dictionary = m["scenarios"][0]["abilities"]
	assert_true(ab.size() > 0)
	for l in ab:
		for a in ab[l]:
			var x: Dictionary = ab[l][a]
			assert_eq(x["usage_rate"]["n"], x["battles"])
			assert_eq(x["win_rate_when_used"]["n"] + x["win_rate_when_unused"]["n"], x["battles"])


func test_batch_report_is_independent_of_workers_and_detects_tampering() -> void:
	var cfg := _tournament(8)
	var r0 := _batch(cfg, 0)
	var r3 := _batch(cfg, 3)
	var m0 := BatchReport.build(r0)
	var m3 := BatchReport.build(r3)
	assert_eq(ReportExporter.content_hash(m0), ReportExporter.content_hash(m3), "mismo informe con 0 y 3 workers")
	assert_eq(ReportExporter.to_markdown(m0), ReportExporter.to_markdown(m3))
	assert_eq(ReportExporter.to_html(m0), ReportExporter.to_html(m3))
	assert_ne(JSON.stringify(m0["measurement"]), "", "el rendimiento va aparte")
	assert_eq(ReportExporter.canonical(m0).has("measurement"), false, "y fuera de la huella")
	# alterar una cifra: la verificacion y la coherencia lo detectan
	var t: Dictionary = JSON.parse_string(ReportExporter.to_json(m0))
	t["scenarios"][0]["outcomes"]["wins"][t["scenarios"][0]["outcomes"]["wins"].keys()[0]]["k"] += 1
	assert_true(ReportVerifier.verify_batch(t, r0).size() > 0)
	assert_true(ReportVerifier.check_batch(t).size() > 0)
	var t2: Dictionary = JSON.parse_string(ReportExporter.to_json(m0))
	t2["scenarios"][0]["outcomes"]["wins"][t2["scenarios"][0]["outcomes"]["wins"].keys()[0]]["wilson95"][0] = 0.0
	assert_true(ReportVerifier.check_batch(t2).size() > 0, "un intervalo de Wilson falso se detecta")
	var t3: Dictionary = JSON.parse_string(ReportExporter.to_json(m0))
	t3["sample"]["finished"] = 1
	assert_true(ReportVerifier.check_batch(t3).size() > 0)


func test_batch_report_separates_errors_and_cancelled_and_shows_sample_size() -> void:
	DirAccess.make_dir_recursive_absolute(TMP)
	var path := TMP + "/boom.json"
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify({"id": "boom", "name": "Boom", "stats": {"SPD": 200}, "basic_attack": false, "scripts": {"s": "fn run(ctx) { let x = 1 / 0; }"},
		"abilities": [{"id": "zap", "targeting": "enemy", "effects": [{"type": "script", "script": "s"}]}], "ai": {"type": "priority_list", "rules": [{"ability": "zap"}]}}))
	f.close()
	var cfg := {"schema": "simhalla.batch/1", "name": "con errores", "master_seed": 3, "repetitions": 5, "base": FAST, "scenarios": [
		{"key": "ok", "entities": [{"path": FX + "attacker_a.json", "overrides": {"team": "A"}}, {"path": FX + "attacker_b.json", "overrides": {"team": "B"}}], "sides": {"A": "A", "B": "B"}},
		{"key": "aborta", "entities": [{"path": path, "overrides": {"team": "A"}}, {"path": FX + "attacker_b.json", "overrides": {"team": "B"}}], "sides": {"A": "Boom", "B": "B"}},
		{"key": "falta", "entities": [{"path": TMP + "/nada.json", "overrides": {"team": "A"}}, {"path": FX + "attacker_b.json", "overrides": {"team": "B"}}], "sides": {"A": "X", "B": "B"}}]}
	var res := _batch(cfg, 2)
	var m := BatchReport.build(res)
	assert_eq(ReportVerifier.check_batch(m), [])
	assert_eq(m["sample"]["errors"], 10)
	assert_eq(m["sample"]["finished"], 5)
	var by := {}
	for s in m["scenarios"]:
		by[s["key"]] = s
	assert_eq(by["aborta"]["sample"]["finished"], 0)
	assert_eq(by["aborta"]["sample"]["aborted"], 5)
	assert_eq(by["aborta"]["outcomes"]["wins"]["Boom"]["n"], 0, "sin resueltos no hay tasa")
	assert_true(by["aborta"]["outcomes"]["wins"]["Boom"]["rate"] == null and by["aborta"]["outcomes"]["wins"]["Boom"]["wilson95"] == null)
	assert_contains(by["aborta"]["errors"][0]["message"], "script_error")
	assert_eq(by["aborta"]["errors"][0]["count"], 5)
	assert_eq(by["falta"]["sample"]["setup_errors"], 5)
	assert_true(by["aborta"]["jobs"].size() >= 1 and by["aborta"]["jobs"][0].has("seed"), "semillas de los trabajos fallidos")
	var md := ReportExporter.to_markdown(m)
	assert_contains(md, "Errores (aparte")
	assert_contains(md, "Resueltos (denominador de las tasas)")
	# cancelado: informe parcial con pendientes
	var big: BatchPlan = BatchPlan.from_dict(BatchModes.duel({"path": FX + "attacker_a.json"}, {"path": FX + "attacker_b.json"}, 200, 1, FAST))["plan"]
	var rn := BatchRunner.new(big, {"workers": 0})
	rn.run_slice(5)
	rn.cancel()
	var part := BatchReport.build(rn.wait())
	assert_eq(part["meta"]["status"], "cancelled")
	assert_eq(part["sample"]["pending"], 195)
	assert_eq(ReportVerifier.check_batch(part), [])
	ContentLibrary._remove_tree(TMP)


func test_batch_report_comparisons_paired_and_independent() -> void:
	var a := {"label": "A", "spec": {"path": FX + "attacker_a.json"}}
	var b := {"label": "B", "spec": {"path": FX + "attacker_b.json"}}
	var paired := BatchModes.compare_ai(a, [{"label": "pasiva", "ai": {"type": "passive"}}, {"label": "activa", "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack"}]}}], b, 12, 2, FAST)
	var m := BatchReport.build(_batch(paired))
	assert_eq(m["comparisons"].size(), 1)
	var c: Dictionary = m["comparisons"][0]
	assert_contains(c["method"], "emparejada")
	assert_eq(c["paired"]["n_pairs"], 12)
	assert_eq(c["paired"]["a_only"] + c["paired"]["b_only"] + c["paired"]["both"] + c["paired"]["neither"], 12)
	assert_true(c["independent"] != null)
	assert_almost(c["paired"]["diff"], c["a_rate"]["rate"] - c["b_rate"]["rate"], 1e-9, "la diferencia emparejada coincide con la de las tasas")
	assert_eq(ReportVerifier.check_batch(m), [])
	paired["seed_mode"] = "per_scenario"
	var m2 := BatchReport.build(_batch(paired))
	assert_contains(m2["comparisons"][0]["method"], "independiente")
	assert_false(m2["comparisons"][0].has("paired"))
	var md := ReportExporter.to_markdown(m)
	assert_contains(md, "Comparaciones entre variantes")
	assert_contains(md, "emparejada")


func test_custom_metrics_and_content_versions_in_batch_report() -> void:
	var lib := ContentLibrary.new("%s/lib%d" % [TMP, Time.get_ticks_usec()])
	assert_true(PackageImporter.new(lib).import_package("res://content/packages/rune_caster").ok())
	var base := FAST.duplicate(true)
	base["library"] = lib.root
	var cfg := BatchModes.gauntlet({"label": "rune", "spec": {"package": "examples/rune_caster"}}, [{"label": "b", "spec": {"path": FX + "attacker_b.json"}}], 6, 3, base)
	cfg["scenarios"][0]["entities"].append({"path": FX + "attacker_b.json", "overrides": {"id": "b2", "team": "B"}})
	var m := BatchReport.build(_batch(cfg, 2))
	assert_eq(m["scenarios"][0]["sample"]["aborted"], 0, str(m["scenarios"][0]["errors"]))
	assert_true(m["scenarios"][0]["custom_metrics"].has("chain_jumps"), "metrica de contenido agregada")
	assert_eq(m["scenarios"][0]["custom_metrics"]["chain_jumps"]["type"], "sum")
	assert_true(m["meta"]["contents"].has("subject__vs__b"))
	assert_eq(str(m["meta"]["contents"]["subject__vs__b"][0]["content"]["hash"]).length(), 64, "huella del contenido en el informe")
	assert_eq(ReportVerifier.check_batch(m), [])
	ContentLibrary._remove_tree(TMP)


# --- exportadores ------------------------------------------------------------------------------------------------------------

func test_three_formats_come_from_the_same_model() -> void:
	var m := _report(_cfg())
	var json := ReportExporter.to_json(m)
	var md := ReportExporter.to_markdown(m)
	var html := ReportExporter.to_html(m)
	var parsed: Dictionary = JSON.parse_string(json)
	assert_eq(ReportExporter.content_hash(parsed), ReportExporter.content_hash(m), "el JSON es el modelo (ida y vuelta)")
	var h := ReportExporter.content_hash(m)
	for text in [md, html]:
		assert_contains(text, h, "huella del informe en cada formato")
		assert_contains(text, m["meta"]["log_hash"])
		assert_contains(text, "Dano")
	assert_contains(md, "| Entidad |")
	assert_contains(md, "# Informe de combate")
	assert_contains(html, "<table>")
	assert_contains(html, "<svg")
	# cifras clave idénticas en los tres
	var dealt: String = ReportDocument.num(m["damage"]["by_entity"]["a"]["dealt"])
	assert_contains(md, dealt)
	assert_contains(html, dealt)
	assert_contains(json, "\"dealt\": %s" % str(m["damage"]["by_entity"]["a"]["dealt"]))


func test_html_is_self_contained_without_network_or_scripts() -> void:
	var html := ReportExporter.to_html(BatchReport.build(_batch(_tournament(4))))
	for banned in ["http://", "https://", "<script", "src=", "@import", "url(", "<link", "<iframe", "onerror", "onclick", "javascript:", "<img", "fetch("]:
		assert_false(html.contains(banned), "el HTML no debe contener '%s'" % banned)
	assert_contains(html, "Content-Security-Policy")
	assert_contains(html, "default-src 'none'")
	assert_contains(html, "<style>")
	assert_contains(html, "<svg")
	assert_contains(html, "prefers-color-scheme")
	assert_contains(html, "viewport")
	assert_true(html.begins_with("<!doctype html>"))
	assert_true(html.length() < 2000000)
	# etiquetas de accesibilidad de las graficas
	assert_contains(html, "role=\"img\"")


func test_hostile_imported_text_is_escaped_in_every_format() -> void:
	var evil_a := "<script>alert(1)</script>|x"
	var evil_b := "b\"'&<img src=x onerror=alert(2)>\n`code`[link](http://e.vil)"
	var cfg := BatchModes.duel({"path": FX + "attacker_a.json"}, {"path": FX + "attacker_b.json"}, 4, 1, FAST, evil_a, evil_b)
	var m := BatchReport.build(_batch(cfg))
	var html := ReportExporter.to_html(m)
	var md := ReportExporter.to_markdown(m)
	assert_false(html.contains("<script"), "sin <script> sin escapar")
	assert_false(html.contains("<img"))
	assert_false(html.contains("onerror=alert(2)>"))
	assert_contains(html, "&lt;script&gt;alert(1)&lt;/script&gt;|x")
	assert_contains(html, "b&quot;&#39;&amp;&lt;img src=x onerror=alert(2)&gt;")
	assert_false(md.contains("<script"), "Markdown sin HTML crudo")
	assert_false(md.contains("<img"))
	assert_contains(md, "&lt;script&gt;")
	assert_contains(md, "\\|x", "el pipe no rompe la tabla")
	assert_false(md.contains("[link](http://e.vil)"), "los corchetes se escapan: no hay enlaces inyectados")
	assert_false(md.contains("`code`"))
	for line in md.split("\n"):
		if line.begins_with("| ") and line.contains("script"):
			assert_true(line.count("|") - line.count("\\|") >= 3, "la fila de la tabla sigue siendo una fila")
	# el JSON conserva el dato original intacto (no es un formato de presentacion)
	assert_contains(ReportExporter.to_json(m), "<script>")
	assert_eq(MarkdownRenderer.esc("a|b\nc"), "a\\|b c")
	assert_eq(HtmlRenderer.esc("<a href=\"x\">&'"), "&lt;a href=&quot;x&quot;&gt;&amp;&#39;")
	assert_eq(HtmlRenderer.esc("a" + char(1) + "b" + char(7)), "ab", "caracteres de control fuera")
	# nombres de entidad hostiles en el informe individual
	var cfg2 := _cfg()
	cfg2["entities"][0]["overrides"]["name"] = "<b>negrita</b>"
	var im := _report(cfg2)
	assert_false(ReportExporter.to_html(im).contains("<b>negrita"))


func test_files_are_written_and_names_validated() -> void:
	var m := _report(_cfg())
	var out := ReportExporter.write_all(m, TMP + "/out", "combate_1")
	assert_eq(out["errors"], [])
	assert_eq(out["paths"].size(), 3)
	for p in out["paths"]:
		assert_true(FileAccess.file_exists(p), p)
		assert_true(FileAccess.get_file_as_string(p).length() > 100)
	assert_eq(JSON.parse_string(FileAccess.get_file_as_string(TMP + "/out/combate_1.json"))["meta"]["log_hash"], m["meta"]["log_hash"])
	for bad in ["../fuera", "a/b", "", "con espacio", "x".repeat(100)]:
		assert_true(ReportExporter.write_all(m, TMP + "/out", bad)["errors"].size() > 0, bad)
	ContentLibrary._remove_tree(TMP)


# --- depuracion ------------------------------------------------------------------------------------------------------------------

func test_debug_inspector_exposes_internal_state_filters_and_explanations() -> void:
	var eng := _rich_engine()
	var dbg := DebugInspector.new(eng)
	var st := dbg.entity_state("a")
	assert_true(st["stats"].has("ATK") and st["stats"]["ATK"].has("modifiers") and st["stats"]["ATK"].has("base"), "desglose de estadisticas con modificadores")
	assert_eq(st["ai"], "scored")
	assert_true(st["ai_memory"].has("obs"), "memoria de IA completa")
	assert_true(st["resources"].has("mana") and st["resources"]["mana"].has("regen_per_turn"))
	assert_true(st["abilities"]["venom"]["state"].has("uses_combat"))
	assert_true(dbg.entity_state("zzz").is_empty())
	assert_true(dbg.rng_states().keys().size() > 0, "estados del RNG por flujo")
	assert_true(dbg.scheduler_state().has("forecast"))
	assert_true(dbg.stat_breakdown("a", "ATK").has("value"))
	# filtros
	var dmg := dbg.filter_events({"type": "damage_dealt"})
	assert_true(dmg.size() > 0)
	for e in dmg:
		assert_eq(e["type"], "damage_dealt")
	var of_b := dbg.filter_events({"entity": "b"})
	for e in of_b:
		assert_true(e["source"] == "b" or e["target"] == "b")
	var by_ab := dbg.filter_events({"ability": "venom", "type": "damage_dealt"})
	assert_true(by_ab.size() > 0)
	var one: Dictionary = dmg[0]
	var chain := dbg.filter_events({"chain_of": int(one["id"])})
	assert_true(chain.size() >= 2 and int(chain[chain.size() - 1]["id"]) == int(one["id"]))
	var root_id := int(chain[0]["id"])
	var desc := dbg.filter_events({"descendants_of": root_id})
	assert_true(desc.size() >= chain.size() - 0)
	assert_eq(dbg.filter_events({"type": "damage_dealt", "limit": 2}).size(), 2)
	assert_true(dbg.filter_events({"from": int(one["id"]), "to": int(one["id"])}).size() == 1)
	# tiradas y explicacion de eventos
	var rolls := dbg.rolls("a")
	assert_true(rolls.size() > 0 and rolls[0].has("chance") and rolls[0].has("roll"))
	var ex := dbg.explain_event(int(one["id"]))
	assert_eq(int(ex["event"]["id"]), int(one["id"]))
	assert_true(ex["causal_chain"].size() >= 2)
	assert_true(dbg.explain_event(999999).is_empty())
	var shielded := eng.log.of_type(EventTypes.EVENT_MODIFIED)
	if shielded.size() > 0:
		var pre_id := int(shielded[0]["data"]["event"])
		assert_true(dbg.explain_event(pre_id)["modifications"].size() >= 1, "modificaciones de un evento")
	# solo lectura: copias
	st["hp"] = -5
	assert_true(dbg.entity_state("a")["hp"] != -5)


func test_debug_validation_causes_and_abort_diagnostics() -> void:
	var prof := BalanceProfile.from_file("res://content/balance/reference_costs.json")
	var rules := Ruleset.from_dict({})
	var bad := DebugInspector.validation_causes({"id": "x", "team": "A", "abilities": [{"id": "z", "targeting": "enemy", "effects": [{"type": "apply_status", "status": "no_existe"}]}]}, prof, rules)
	assert_true(bad["technical"].size() > 0 or bad["balance"]["technical_errors"].size() > 0)
	var over := DebugInspector.validation_causes({"id": "x", "team": "A", "stats": {"ATK": 9000}}, prof, rules, "regulated", "small")
	assert_eq(over["technical"], [])
	assert_false(over["balance"]["valid"])
	assert_contains(" ".join(over["balance"]["errors"]), "[presupuesto]")
	var boom := ent("a", "A", {"stats": {"SPD": 100}, "scripts": {"s": "fn run(ctx) { let x = 1 / 0; }"}, "abilities": [{"id": "z", "targeting": "enemy", "effects": [{"type": "script", "script": "s"}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "z"}]}})
	var eng := engine([boom, ent("t", "B", {"stats": {"SPD": 1}})], 1)
	eng.run()
	var diag := DebugInspector.new(eng).abort_diagnostic(5)
	assert_eq(diag["error"]["code"], "script_error")
	assert_true(diag["last_events"].size() <= 5 and diag["last_events"].size() > 0)
	var ok_eng := _rich_engine()
	assert_true(DebugInspector.new(ok_eng).abort_diagnostic().is_empty())
	# el informe de un combate abortado lo refleja (aborto != resultado)
	var m: Dictionary = IndividualReport.build(eng, {})["report"]
	assert_eq(m["result"]["outcome"], "aborted")
	assert_eq(m["result"]["error"]["code"], "script_error")
	assert_contains(ReportExporter.to_markdown(m), "Error tecnico")


func test_debug_channel_is_separate_from_the_ai_view() -> void:
	# el codigo de IA y de scripts no referencia el depurador
	for dir in ["res://src/ai", "res://src/scripting"]:
		var d := DirAccess.open(dir)
		for f in d.get_files():
			if f.ends_with(".gd"):
				var text := FileAccess.get_file_as_string(dir.path_join(f))
				assert_false(text.contains("DebugInspector"), "%s/%s no debe usar el depurador" % [dir, f])
				assert_false(text.contains("IndividualReport"), "%s/%s no debe usar informes" % [dir, f])
	# la vista de la IA no contiene los campos de depuracion de OTRAS entidades
	var eng := _rich_engine()
	var b := eng.get_entity("b")
	b.script_vars["secreto_depuracion"] = 123
	b.ai_memory["vars"]["secreto_ia"] = "x"
	var a := eng.get_entity("a")
	var view := ViewBuilder.build(eng, a, TurnState.new(a, 1))
	var text := JSON.stringify(view["others"])
	for leak in ["secreto_depuracion", "secreto_ia", "script_vars", "ai_memory", "modifiers", "rng", "causal"]:
		assert_false(text.contains(leak), "la vista limitada no filtra '%s'" % leak)
	var dbg_state := DebugInspector.new(eng).entity_state("b")
	assert_eq(dbg_state["script_vars"]["secreto_depuracion"], 123, "el depurador SI lo ve")


func test_report_models_match_the_public_schema_and_seeds_survive_json() -> void:
	var v := SchemaValidator.new()
	var im := _report(_cfg())
	assert_eq(v.validate("report.schema.json", im), [])
	var res := _batch(_tournament(3))
	var bm := BatchReport.build(res)
	assert_eq(v.validate("report.schema.json", bm), [])
	assert_true(v.validate("report.schema.json", {"schema": "simhalla.report/1", "kind": "otro", "meta": {"engine_version": "x"}}).size() > 0)
	# semillas de 64 bits: texto exacto tras exportar y releer (un numero JSON perderia precision)
	var parsed: Dictionary = JSON.parse_string(ReportExporter.to_json(bm))
	for s in parsed["scenarios"]:
		for j in s["jobs"]:
			assert_true(j["seed"] is String)
			assert_eq(j["seed"], str(res.records[int(j["index"])]["seed"]), "semilla exacta de 64 bits")
	assert_eq(ReportVerifier.verify_batch(parsed, res), [], "el informe releido sigue verificandose")
	var back: Dictionary = JSON.parse_string(ReportExporter.to_json(im))
	assert_true(ReportVerifier.reproduce_individual(back)["ok"], "reproducible tras releer el JSON")
