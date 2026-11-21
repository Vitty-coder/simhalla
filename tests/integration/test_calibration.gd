extends TestCase
## Calibrador empirico de costes (D-118): matematica auxiliar, regresion sobre datos sinteticos, calibracion real determinista,
## propuesta valida e ILUSTRATIVA, errores/avisos, modelo de aplicacion y valores por defecto.

const FX := "res://content/fixtures/entities/"
const FAST := {"ruleset_overrides": {"victory": {"limits": {"max_turns": 60, "stagnation_turns": 30}}}}
const TMP := "user://_tests_calib"


func _contestants(names: Array) -> Array:
	var out: Array = []
	for n in names:
		out.append({"label": n, "spec": {"path": FX + n + ".json"}, "data": EntityFactory.load_json(FX + n + ".json")})
	return out


func _calibrate(names: Array, opts: Dictionary = {}) -> Dictionary:
	var o := {"reps": 2, "master_seed": 3, "base": FAST}
	o.merge(opts, true)
	return BalanceCalibrator.calibrate(_contestants(names), BalanceProfile.from_file("res://content/balance/reference_costs.json"),
		Ruleset.from_file("res://content/rulesets/default_ruleset.json"), OperationRegistry.new(), o)


func test_math_helpers() -> void:
	assert_eq(BalanceCalibrator.spearman([1, 2, 3, 4], [10, 20, 30, 40]), 1.0)
	assert_eq(BalanceCalibrator.spearman([1, 2, 3, 4], [4, 3, 2, 1]), -1.0)
	assert_eq(BalanceCalibrator.spearman([1, 1, 1], [1, 2, 3]), 0.0, "sin varianza")
	assert_eq(BalanceCalibrator.spearman([1], [1]), 0.0)
	assert_eq(BalanceCalibrator._ranks([5, 1, 5, 3]), [3.5, 1.0, 3.5, 2.0], "empates promediados")
	var x := BalanceCalibrator._solve([[2.0, 1.0], [1.0, 3.0]], [5.0, 10.0])
	assert_true(absf(x[0] - 1.0) < 1e-9 and absf(x[1] - 3.0) < 1e-9)
	assert_eq(BalanceCalibrator._solve([[1.0, 2.0], [2.0, 4.0]], [1.0, 2.0]), [], "singular")
	assert_eq(BalanceCalibrator.category_of("stat_credit"), "stats")
	assert_eq(BalanceCalibrator.category_of("modifier_credit"), "stats")
	assert_eq(BalanceCalibrator.category_of("ability"), "abilities")
	assert_eq(BalanceCalibrator.category_of("script"), "other")
	assert_eq(BalanceCalibrator._num(1.5), "1.5")
	assert_eq(BalanceCalibrator._num(2.0), "2")
	assert_eq(BalanceCalibrator._bump("0.1.0"), "0.1.1")


func test_fit_recovers_which_category_gives_more_power_per_point() -> void:
	# poder = 0.02 * puntos_stats + 0.005 * puntos_abilities: las stats rinden 4x mas por punto
	var rows: Array = []
	var y: Array = []
	var total: Array = []
	var data := [[100.0, 400.0], [300.0, 100.0], [50.0, 50.0], [400.0, 300.0], [200.0, 500.0], [350.0, 450.0], [10.0, 300.0], [250.0, 20.0]]
	for d in data:
		rows.append({"stats": d[0], "abilities": d[1], "statuses": 0.0, "resources": 0.0, "other": 0.0})
		y.append(0.02 * d[0] + 0.005 * d[1])
		total.append(d[0] + d[1])
	var f := BalanceCalibrator._fit(y, rows, total)
	assert_true(f["usable"], str(f["warnings"]))
	assert_true(f["multipliers"]["stats"] > f["multipliers"]["abilities"] * 1.5, "las stats rinden mas: %s" % str(f["multipliers"]))
	assert_false(f["identifiable"]["statuses"], "sin varianza: no identificable")
	assert_eq(f["multipliers"]["statuses"], 1.0)
	for k in BalanceCalibrator.SCALABLE:
		assert_true(f["multipliers"][k] >= BalanceCalibrator.MULT_MIN and f["multipliers"][k] <= BalanceCalibrator.MULT_MAX, k)
	# coste que no predice el poder: no se propone nada
	var anti: Array = y.map(func(v): return -v)
	var g := BalanceCalibrator._fit(anti, rows, total)
	assert_false(g["usable"])
	assert_contains(" ".join(g["warnings"]), "NO predice")
	# todos cuestan lo mismo
	var same: Array = total.map(func(_t): return 100.0)
	assert_false(BalanceCalibrator._fit(y, rows, same)["usable"])


func test_real_calibration_is_deterministic_valid_and_illustrative() -> void:
	var names := ["attacker_a", "attacker_b", "glass_cannon", "slow_tank"]
	var a := _calibrate(names)
	assert_true(a["ok"], str(a["errors"]))
	assert_eq(a["summary"]["duels"], 24, "6 parejas x 2 lados x 2 repeticiones")
	assert_eq(a["entities"].size(), 4)
	for e in a["entities"]:
		assert_true(e["score"] >= 0.0 and e["score"] <= 1.0)
		assert_true(["acorde", "subvalorado", "sobrevalorado"].has(e["verdict"]))
		assert_eq(e["games"], 6 * 2, "3 rivales x 2 lados x 2 repeticiones")
	var b := _calibrate(names)
	assert_eq(a["result_fingerprint"], b["result_fingerprint"], "misma semilla, mismo torneo")
	assert_eq(JSON.stringify(a["categories"]), JSON.stringify(b["categories"]))
	var c := _calibrate(names, {"master_seed": 99})
	assert_ne(a["result_fingerprint"], c["result_fingerprint"], "otra semilla, otro torneo")
	assert_contains(" ".join(a["warnings"]), "poco fiable", "4 contendientes < 6 recomendados")
	assert_contains(" ".join(a["warnings"]), "pocas repeticiones")
	if a["suggested_profile"] != null:
		var sp := BalanceProfile.from_dict(a["suggested_profile"])
		assert_true(sp.is_valid(), str(sp.errors))
		assert_true(sp.illustrative, "una propuesta calibrada siempre es ilustrativa")
		assert_eq(sp.id, "reference_costs_cal")
		assert_eq(sp.version, "0.1.1")
		assert_contains(sp.description, "PROPUESTA")
		assert_true(a["summary"].has("spearman_after"))
		assert_true(sp.budgets.keys() == BalanceProfile.from_file("res://content/balance/reference_costs.json").budgets.keys(), "presupuestos intactos")
	var md := BalanceCalibrator.to_markdown(a)
	assert_contains(md, "PROPUESTA ILUSTRATIVA")
	assert_contains(md, "Spearman")


func test_errors_and_edge_cases() -> void:
	var few := _calibrate(["attacker_a", "attacker_b"])
	assert_false(few["ok"])
	assert_contains(few["errors"][0], "al menos 4")
	var dup := BalanceCalibrator.calibrate(_contestants(["attacker_a", "attacker_a", "attacker_b", "slow_tank"]), BalanceProfile.from_file("res://content/balance/reference_costs.json"),
		Ruleset.from_file("res://content/rulesets/default_ruleset.json"), OperationRegistry.new(), {"base": FAST})
	assert_false(dup["ok"])
	assert_contains(dup["errors"][0], "repetida")
	var tech := BalanceCalibrator.calibrate(_contestants(["attacker_a", "attacker_b", "slow_tank", "glass_cannon"]), BalanceProfile.from_file("res://content/balance/technical_profile.json"),
		Ruleset.from_file("res://content/rulesets/default_ruleset.json"), OperationRegistry.new(), {"base": FAST})
	assert_false(tech["ok"])
	assert_contains(tech["errors"][0], "no define costes")
	assert_contains(BalanceCalibrator.to_markdown(few), "Error")


func test_model_calibrates_library_packages_and_saves_the_proposal() -> void:
	var a := AppController.new("%s/m%d" % [TMP, Time.get_ticks_usec()])
	assert_eq(a.boot(), [])
	assert_eq(a.install_examples()["errors"], [])
	var chars := ["examples/arcane_duelist", "examples/iron_vanguard", "examples/rune_caster"]
	var few := a.rules.calibrate(chars, {"reps": 2})
	assert_false(few["ok"], "3 personajes no bastan")
	var bad := a.rules.calibrate(["no/existe", "x/y", "a/b", "c/d"])
	assert_false(bad["ok"])
	assert_false(bool(a.rules.save_calibrated({"suggested_profile": null})["ok"]))
	# guardado con resolucion de colisiones
	var fake := {"suggested_profile": BalanceProfile.from_file("res://content/balance/reference_costs.json").to_dict()}
	fake["suggested_profile"]["id"] = "user/prueba_cal"
	var s1: Dictionary = a.rules.save_calibrated(fake)
	assert_true(s1["ok"], str(s1))
	assert_eq(s1["id"], "user/prueba_cal")
	assert_eq(a.storage.history()[a.storage.history().size() - 1]["action"], "calibrate")
	ContentLibrary._remove_tree(TMP)


func test_default_profile_budget_and_mode_are_set_and_illustrative() -> void:
	assert_eq(AppStorage.DEFAULT_SETTINGS["default_profile"], "builtin/reference_costs")
	assert_eq(AppStorage.DEFAULT_SETTINGS["default_budget"], "standard")
	assert_eq(AppStorage.DEFAULT_SETTINGS["default_mode"], "free")
	var a := AppController.new("%s/d%d" % [TMP, Time.get_ticks_usec()])
	assert_eq(a.boot(), [])
	var p := a.profile()
	assert_eq(p.id, "reference_costs")
	assert_true(p.illustrative)
	assert_eq(p.default_budget, "standard")
	assert_eq(a.budget(), "standard")
	assert_eq(a.mode(), "free")
	assert_true(p.has_costs())
	assert_true(p.budgets.has("standard"))
	ContentLibrary._remove_tree(TMP)


func test_cooperative_calibration_through_the_model_and_screen() -> void:
	var a := AppController.new("%s/c%d" % [TMP, Time.get_ticks_usec()])
	assert_eq(a.boot(), [])
	assert_eq(a.install_examples()["errors"], [])
	# el modelo por tramos == la version sincrona (mismo torneo)
	var ids := ["examples/arcane_duelist", "examples/iron_vanguard", "examples/rune_caster"]
	assert_false(bool(a.rules.begin_calibration(ids, {"reps": 2})["ok"]), "menos de 4: error y sin trabajo en marcha")
	assert_true(a.rules.calib_job == null)
	assert_false(a.rules.calibration_step(), "sin trabajo no hay nada que avanzar")
	# pantalla con solo 3 personajes: error claro y sin torneo en marcha
	var m: MainUI = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	m.app = a
	m.build_ui()
	a.go("rules")
	var rs := m.screen_node as RulesScreen
	assert_true(m.find_child("calib_run_btn", true, false) != null)
	assert_true(m.find_child("calib_pick_0", true, false) != null)
	for i in 3:
		(m.find_child("calib_pick_%d" % i, true, false) as CheckBox).toggled.emit(true)
	(m.find_child("calib_run_btn", true, false) as Button).pressed.emit()
	assert_false(rs.calib_running)
	assert_contains(str(a.rules.calib_result.get("errors", [])), "al menos 4")
	m.free()
	ContentLibrary._remove_tree(TMP)


func test_job_runs_in_slices_and_matches_the_synchronous_result() -> void:
	var names := ["attacker_a", "attacker_b", "glass_cannon", "slow_tank"]
	var sync := _calibrate(names)
	var b := BalanceCalibrator.begin(_contestants(names), BalanceProfile.from_file("res://content/balance/reference_costs.json"),
		Ruleset.from_file("res://content/rulesets/default_ruleset.json"), OperationRegistry.new(), {"reps": 2, "master_seed": 3, "base": FAST})
	assert_true(b["ok"], str(b))
	var job: BalanceCalibrator.Job = b["job"]
	var slices := 0
	while not job.is_done() and slices < 10000:
		job.step(1)
		slices += 1
	assert_true(slices > 1, "se ejecuta en varios tramos")
	var res := job.finish()
	assert_true(res["ok"])
	assert_eq(res["result_fingerprint"], sync["result_fingerprint"], "por tramos == sincrono")
	assert_eq(JSON.stringify(res["categories"]), JSON.stringify(sync["categories"]))
	# cancelar
	var b2 := BalanceCalibrator.begin(_contestants(names), BalanceProfile.from_file("res://content/balance/reference_costs.json"),
		Ruleset.from_file("res://content/rulesets/default_ruleset.json"), OperationRegistry.new(), {"reps": 2, "master_seed": 3, "base": FAST})
	var j2: BalanceCalibrator.Job = b2["job"]
	j2.step(1)
	j2.cancel()
	var cr := j2.finish()
	assert_false(cr["ok"])
	assert_true(cr["cancelled"])


## Crea variantes de un personaje de ejemplo (otra id y estadisticas) para tener >= 4 personajes distintos en la biblioteca.
func _install_variants(a: AppController, n: int) -> Array:
	var ids: Array = []
	var specs := [{"HP": 900, "ATK": 160, "DEF": 80}, {"HP": 1800, "ATK": 90, "DEF": 260}, {"HP": 1200, "ATK": 120, "DEF": 150}]
	for i in n:
		var dir := "%s/var%d_%d" % [TMP, i, Time.get_ticks_usec()]
		DirAccess.make_dir_recursive_absolute(dir)
		var mf := {"schema": "simhalla.manifest/1", "id": "test/var%d" % i, "version": "1.0.0", "type": "character", "name": "Variante %d" % i, "license": "CC0-1.0"}
		var st: Dictionary = (specs[i % specs.size()] as Dictionary).duplicate()
		st["SPD"] = 90 + 5 * i
		var ch := {"schema": "simhalla.character/1", "name": "Variante %d" % i, "stats": st, "basic_attack": true}
		for pair in [["manifest.json", mf], ["character.json", ch]]:
			var f := FileAccess.open(dir.path_join(pair[0]), FileAccess.WRITE)
			f.store_string(JSON.stringify(pair[1]))
			f.close()
		var r := a.importer.commit(dir)
		assert_true(r["ok"], str(r))
		ids.append("test/var%d" % i)
	return ids


func test_model_calibrates_real_library_packages_sync_and_by_slices_and_saves() -> void:
	var a := AppController.new("%s/p%d" % [TMP, Time.get_ticks_usec()])
	assert_eq(a.boot(), [])
	assert_eq(a.install_examples()["errors"], [])
	var ids := ["examples/arcane_duelist", "examples/iron_vanguard", "examples/rune_caster"]
	ids.append_array(_install_variants(a, 1))
	var sync := a.rules.calibrate(ids, {"reps": 2, "master_seed": 5})
	assert_true(sync["ok"], str(sync["errors"]))
	assert_eq(sync["entities"].size(), 4)
	assert_eq(sync["summary"]["duels"], 6 * 2 * 2)
	# por tramos (como la interfaz) == sincrono
	assert_true(a.rules.begin_calibration(ids, {"reps": 2, "master_seed": 5})["ok"])
	assert_true(a.rules.calib_job != null)
	var guard := 0
	while a.rules.calibration_step(1) and guard < 100000:
		guard += 1
	assert_true(a.rules.calib_job == null)
	assert_true(a.rules.calib_result["ok"], str(a.rules.calib_result))
	assert_eq(a.rules.calib_result["result_fingerprint"], sync["result_fingerprint"])
	# con version explicita
	assert_true(a.rules.calibrate(["examples/arcane_duelist@1.0.0", "examples/iron_vanguard@1.0.0", "examples/rune_caster@1.0.0", "test/var0@1.0.0"], {"reps": 2, "master_seed": 5})["ok"])
	# guardar la propuesta (si la hay) como perfil versionado ilustrativo
	if sync["suggested_profile"] != null:
		var sv: Dictionary = a.rules.save_calibrated(sync)
		assert_true(sv["ok"], str(sv))
		var d := a.rules.profile_detail(str(sv["id"]), str(sv["version"]))
		assert_true(bool(d["illustrative"]))
		assert_true(bool(d["has_costs"]))
	ContentLibrary._remove_tree(TMP)


func test_calibration_screen_end_to_end() -> void:
	var a := AppController.new("%s/s%d" % [TMP, Time.get_ticks_usec()])
	assert_eq(a.boot(), [])
	assert_eq(a.install_examples()["errors"], [])
	_install_variants(a, 1)
	var m: MainUI = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	m.app = a
	m.build_ui()
	a.go("rules")
	var rs := m.screen_node as RulesScreen
	var picks := 0
	while m.find_child("calib_pick_%d" % picks, true, false) != null:
		(m.find_child("calib_pick_%d" % picks, true, false) as CheckBox).toggled.emit(true)
		picks += 1
	assert_eq(picks, 4)
	rs.calib_reps = 2
	(m.find_child("calib_run_btn", true, false) as Button).pressed.emit()
	assert_true(rs.calib_running)
	var guard := 0
	while rs.calib_running and guard < 20000:
		rs._process(0.016)
		guard += 1
	assert_false(rs.calib_running)
	assert_true(a.rules.calib_result["ok"], str(a.rules.calib_result))
	var txt := ""
	for l in rs.find_children("*", "Label", true, false):
		txt += (l as Label).text + "\n"
	assert_contains(txt, "Spearman")
	if a.rules.calib_result["suggested_profile"] != null:
		var sb := m.find_child("calib_save_btn", true, false) as Button
		assert_true(sb != null)
		sb.pressed.emit()
		assert_true(a.rules.profiles().filter(func(p): return str(p["id"]).ends_with("_cal")).size() == 1, "perfil calibrado guardado")
	# cancelar a mitad
	var rs2 := m.screen_node as RulesScreen
	(m.find_child("calib_run_btn", true, false) as Button).pressed.emit()
	rs2._process(0.016)
	(m.find_child("calib_cancel_btn", true, false) as Button).pressed.emit()
	assert_false(rs2.calib_running)
	assert_true(a.rules.calib_job == null)
	m.free()
	ContentLibrary._remove_tree(TMP)
