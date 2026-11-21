extends TestCase
## Fase 9 (aplicacion): flujo completo importacion -> duelo/lote -> informe usable, a traves de los MODELOS de aplicacion (sin nodos)
## y de la INTERFAZ Godot automatizada en modo headless. Localizacion, retratos, adaptabilidad y proteccion de datos.

const TMP := "user://_tests_phase9b"
const FX := "res://content/fixtures/entities/"
var _n := 0


func _app() -> AppController:
	_n += 1
	var a := AppController.new("%s/a%d_%d" % [TMP, Time.get_ticks_usec(), _n])
	assert_eq(a.boot(), [])
	return a


func _pkg_dir(stats: Dictionary, id: String = "t/hero", version: String = "1.0.0", assets: Dictionary = {}) -> String:
	_n += 1
	var d := "%s/pkg%d_%d" % [TMP, Time.get_ticks_usec(), _n]
	var files := {"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": id, "version": version, "type": "character", "name": id.get_file() + " " + version}),
		"character.json": JSON.stringify({"schema": "simhalla.character/1", "name": "Hero", "stats": stats, "basic_attack": true})}
	files.merge(assets, true)
	for rel in files:
		var p: String = d.path_join(rel)
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var f := FileAccess.open(p, FileAccess.WRITE)
		if files[rel] is PackedByteArray:
			f.store_buffer(files[rel])
		else:
			f.store_string(files[rel])
		f.close()
	return d


func _import(a: AppController, stats: Dictionary = {"ATK": 150}, id: String = "t/hero", version: String = "1.0.0") -> void:
	var r := a.importer.commit(_pkg_dir(stats, id, version))
	assert_true(r["ok"], str(r["errors"]))


# --- importacion -------------------------------------------------------------------------------------------------------------

func test_import_preview_collision_policies_and_budget() -> void:
	var a := _app()
	var d := _pkg_dir({"ATK": 150})
	var pv := a.importer.preview(d)
	assert_true(pv["ok"], str(pv["errors"]))
	assert_eq(pv["id"], "t/hero")
	assert_false(pv["collision"]["exists"])
	assert_eq(a.library.entries().size(), 0, "la vista previa no almacena")
	assert_true(pv["balance"].has("creation_cost"), "coste y presupuesto antes de importar")
	assert_almost(pv["balance"]["creation_cost"], 30.0)
	assert_true(a.importer.commit(d)["ok"])
	assert_eq(a.library.entries().size(), 1)
	var again := a.importer.preview(d)
	assert_true(again["collision"]["exists"] and again["collision"]["same"], "mismo contenido: idempotente")
	# contenido distinto con el mismo id@version: colision explicita
	var d2 := _pkg_dir({"ATK": 900})
	var pv2 := a.importer.preview(d2)
	assert_true(pv2["collision"]["exists"] and not pv2["collision"]["same"])
	assert_eq(pv2["collision"]["next_version"], "1.0.1")
	assert_false(pv2["ok"])
	var rej := a.importer.commit(d2)
	assert_false(rej["ok"])
	assert_contains(" ".join(rej["errors"]), "[version_conflicto]")
	assert_eq(a.library.entries().size(), 1, "rechazado: nada cambia")
	var nv := a.importer.commit(d2, "new_version")
	assert_true(nv["ok"], str(nv["errors"]))
	assert_eq(nv["version"], "1.0.1")
	assert_eq(a.storage.library.versions("t/hero"), ["1.0.0", "1.0.1"])
	assert_eq(a.storage.library.entry("t/hero", "1.0.0")["hash"], a.importer.preview(d)["hash"], "la original sigue intacta")
	# modo reglamentado: un personaje fuera de presupuesto no se puede importar
	a.save_settings({"default_mode": "regulated", "default_budget": "small"})
	var big := a.importer.preview(_pkg_dir({"ATK": 5000}, "t/big"))
	assert_false(big["ok"])
	assert_contains(" ".join(big["errors"]), "[presupuesto]")
	a.save_settings({"default_mode": "free"})
	assert_true(a.importer.preview(_pkg_dir({"ATK": 5000}, "t/big"))["ok"], "libre: solo avisa")
	# paquete invalido: errores por archivo y ruta
	var bad_dir := _pkg_dir({"ATK": "mucho"}, "t/mal")
	var bad := a.importer.preview(bad_dir)
	assert_false(bad["ok"])
	assert_true(bad["errors"].size() > 0)


# --- biblioteca ---------------------------------------------------------------------------------------------------------------

func test_library_search_filters_versions_and_detail_with_cost() -> void:
	var a := _app()
	_import(a, {"ATK": 150}, "t/hero", "1.0.0")
	_import(a, {"ATK": 160}, "t/hero", "1.1.0")
	_import(a, {"MAG": 130}, "t/mage", "1.0.0")
	assert_eq(a.library.entries().size(), 3)
	assert_eq(a.library.entries({"query": "mage"}).size(), 1)
	assert_eq(a.library.entries({"query": "HERO"}).size(), 2, "insensible a mayusculas")
	assert_eq(a.library.entries({"type": "ai"}).size(), 0)
	assert_eq(a.library.versions_of("t/hero"), ["1.0.0", "1.1.0"])
	var latest := a.library.entries({"query": "hero"}).filter(func(e): return e["latest"])
	assert_eq(latest.size(), 1)
	assert_eq(latest[0]["version"], "1.1.0")
	var d := a.library.detail("t/hero", "1.1.0")
	assert_true(d["ok"])
	assert_eq(d["integrity"], "ok")
	assert_eq(d["character"]["stats"]["ATK"], 160.0)
	assert_true(d["cost"].has("creation_cost") and d["cost"]["budget"]["points"] > 0.0)
	assert_eq(d["cost"]["labels"].size(), 1, "etiqueta de perfil ilustrativo junto al coste")
	assert_true(d["versions"].size() == 2)
	assert_false(a.library.detail("t/nada", "1.0.0")["ok"])
	# integridad: contenido alterado en disco
	var f := FileAccess.open(a.storage.library.entry_dir("t/mage", "1.0.0").path_join("character.json"), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	var bad := a.library.detail("t/mage", "1.0.0")
	assert_false(bad["ok"])
	assert_eq(bad["integrity"], "alterado")
	assert_false(a.library.entries({"query": "mage"})[0]["valid"])


# --- duelo, visor, guardado e informe ------------------------------------------------------------------------------------------

func test_duel_setup_shows_cost_versions_and_blocks_regulated_violations() -> void:
	var a := _app()
	_import(a, {"ATK": 150}, "t/hero", "1.0.0")
	_import(a, {"ATK": 9000}, "t/giant", "1.0.0")
	var dm := a.duel
	assert_false(dm.validate()["can_start"], "sin contendientes")
	dm.add_package("t/hero")
	assert_false(dm.validate()["can_start"])
	assert_contains(" ".join(dm.validate()["errors"]), "al menos dos")
	dm.add_file(FX + "attacker_b.json")
	var v := dm.validate()
	assert_true(v["can_start"], str(v["errors"]))
	assert_eq(v["entities"][0]["resolved"]["version"], "1.0.0", "version resuelta visible antes del combate")
	assert_eq(str(v["entities"][0]["resolved"]["hash"]).length(), 64)
	assert_almost(v["entities"][0]["cost"], 30.0)
	assert_eq(v["mode"], "free")
	assert_eq(v["mode_label"], "Modo libre")
	assert_contains(v["illustrative_notice"], "ILUSTRATIVO")
	dm.add_package("t/giant", "*", "B")
	dm.budget = "small"
	assert_true(dm.validate()["can_start"], "libre: exceder el presupuesto no bloquea")
	assert_true(dm.validate()["warnings"].size() > 0)
	dm.mode = "regulated"
	var vr := dm.validate()
	assert_false(vr["can_start"])
	assert_eq(vr["mode_label"], "Modo reglamentado")
	assert_contains(" ".join(vr["errors"]), "[presupuesto]")
	var started := dm.start()
	assert_false(started["ok"], "reglamentado fuera de presupuesto: el combate no empieza")
	# configuracion inexistente / sin equipos
	dm.reset()
	dm.add_package("t/hero", "9.*")
	dm.add_file(FX + "attacker_b.json")
	assert_contains(" ".join(dm.validate()["errors"]), "[no_encontrado]")
	dm.reset()
	dm.add_package("t/hero", "*", "A")
	dm.add_file(FX + "attacker_b.json", "A")
	assert_contains(" ".join(dm.validate()["errors"]), "dos equipos")


func test_viewer_controls_rewind_inspection_save_and_report() -> void:
	var a := _app()
	_import(a)
	a.duel.add_package("t/hero")
	a.duel.add_file(FX + "attacker_b.json")
	a.duel.seed_value = 4
	var st := a.duel.start()
	assert_true(st["ok"], str(st["errors"]))
	var vm: ViewerModel = st["viewer"]
	assert_eq(vm.position()["step"], 0)
	assert_true(vm.total_steps() > 5)
	vm.play()
	assert_true(vm.playing)
	vm.set_speed(4)
	assert_eq(vm.tick(), 4, "velocidad = pasos por tick")
	vm.pause()
	assert_eq(vm.tick(), 0)
	vm.step_action()
	assert_eq(vm.position()["step"], 5)
	var snap5: Dictionary = vm.view()["snapshot"]
	vm.step_turn()
	vm.step_turn()
	vm.rewind(3)
	var back: int = vm.position()["step"]
	vm.seek(5)
	assert_eq(vm.view()["snapshot"]["entities"], snap5["entities"], "retroceder reconstruye exactamente el estado")
	assert_true(back < vm.total_steps())
	vm.seek(1000000)
	assert_true(vm.position()["finished"], "seek acotado al final")
	assert_eq(vm.position()["step"], vm.total_steps())
	var v := vm.view()
	assert_true(v["log"].size() > 0 and v["log"][0]["text"] != "")
	assert_true(v["result"].has("outcome"))
	# registro legible: solo eventos visibles
	for line in v["log"]:
		assert_true(EventText.is_visible(str(line["type"])))
	# inspeccion de un evento de dano
	var dmg: Array = v["log"].filter(func(l): return l["type"] == "damage_dealt")
	assert_true(dmg.size() > 0)
	vm.select_event(int(dmg[0]["id"]))
	var ins := vm.inspect()
	assert_true(ins["causal_chain"].size() >= 2 and ins["detail"].size() > 0)
	assert_true(ins["detail"].any(func(d): return d[0] == "premitigation"), "formulas/tiradas del dano visibles")
	# repetir con la misma semilla / reiniciar
	var hash1: String = vm.session.result().log_hash
	vm.repeat_same_seed()
	assert_eq(vm.position()["step"], 0)
	vm.to_end()
	assert_eq(vm.session.result().log_hash, hash1)
	# guardar: combate fijado + informe verificable; reproducir desde guardado
	var sv := vm.save("Mi duelo", false)
	assert_true(sv["ok"], str(sv))
	var rp := vm.save_report(str(sv["id"]))
	assert_true(rp["ok"], str(rp))
	assert_eq(a.storage.verify_report(str(rp["id"])), [])
	var rv := ViewerModel.from_battle(a, str(sv["id"]))
	assert_true(rv["ok"], str(rv["errors"]))
	var v2: ViewerModel = rv["viewer"]
	assert_true(v2.matches_saved)
	assert_eq(v2.source_battle_id, sv["id"])
	v2.to_end()
	assert_eq(v2.session.result().log_hash, hash1, "el combate guardado se reproduce idéntico")
	assert_false(ViewerModel.from_battle(a, "b9999")["ok"])


func test_batch_model_end_to_end_with_pinned_versions_and_report() -> void:
	var a := _app()
	_import(a, {"ATK": 150}, "t/hero", "1.0.0")
	_import(a, {"ATK": 300}, "t/hero", "1.1.0")
	var bm := a.batch
	var spec := {"mode": "duel", "reps": 6, "master_seed": 3, "a": {"package": "t/hero"}, "b": {"path": FX + "attacker_b.json"}, "label_a": "hero", "label_b": "b"}
	var p := bm.prepare(spec)
	assert_true(p["ok"], str(p["errors"]))
	assert_eq(p["jobs"], 6)
	assert_eq(bm.refs[0]["version"], "1.1.0", "'*' se fija a la version exacta")
	assert_eq(str(bm.plan.scenarios[0]["entities"][0]["hash"]).length(), 64)
	assert_true(bm.plan.scenarios[0]["entities"][1].has("data"), "entidad suelta inline")
	assert_true(bm.start(0))
	var guard := 0
	while bm.is_running() and guard < 200:
		bm.step(2, 5)
		guard += 1
	assert_false(bm.is_running())
	assert_eq(bm.result.executed, 6)
	var sv := bm.save("Lote hero")
	assert_true(sv["ok"], str(sv))
	assert_true(a.storage.references_to("package", "t/hero", "1.1.0").size() == 1)
	assert_contains(a.storage.remove_package("t/hero", "1.1.0"), "[referenciado]")
	var rp := bm.save_report()
	assert_true(rp["ok"], str(rp))
	assert_eq(a.storage.verify_report(str(rp["id"])), [])
	# cancelacion
	var big := a.batch
	assert_true(big.prepare({"mode": "duel", "reps": 300, "master_seed": 1, "a": {"path": FX + "attacker_a.json"}, "b": {"path": FX + "attacker_b.json"}})["ok"])
	big.start(0)
	big.step(3, 5)
	big.cancel()
	assert_false(big.is_running())
	assert_eq(big.result.status, "cancelled")
	assert_true(big.result.executed < 300)
	# modalidades y errores
	assert_false(bm.prepare({"mode": "magia"})["ok"])
	assert_true(bm.prepare({"mode": "tournament", "reps": 2, "master_seed": 1, "contestants": [{"label": "a", "spec": {"path": FX + "attacker_a.json"}}, {"label": "b", "spec": {"path": FX + "attacker_b.json"}}, {"label": "t", "spec": {"path": FX + "slow_tank.json"}}]})["ok"])
	assert_false(bm.prepare({"mode": "duel", "reps": 2, "master_seed": 1, "a": {"package": "t/nada"}, "b": {"path": FX + "attacker_b.json"}})["ok"])


func test_reports_model_lists_opens_exports_verifies_and_protects() -> void:
	var a := _app()
	_import(a)
	a.duel.add_package("t/hero")
	a.duel.add_file(FX + "attacker_b.json")
	var vm: ViewerModel = a.duel.start()["viewer"]
	var bid: String = vm.save("Combate X", false)["id"]
	var made := a.reports.from_battle(bid)
	assert_true(made["ok"], str(made))
	assert_eq(a.reports.list().size(), 1)
	assert_eq(a.reports.list({"query": "combate"}).size(), 1)
	var rid: String = made["id"]
	assert_contains(a.reports.open(rid, "md"), "# Informe de combate")
	assert_contains(a.reports.open(rid, "html"), "<!doctype html>")
	assert_eq(a.reports.model(rid)["kind"], "individual")
	assert_true(a.reports.document(rid).blocks.size() > 10)
	assert_eq(a.reports.verify(rid), [])
	var ex := a.reports.export_files(rid, a.storage.root.path_join("exports"))
	assert_eq(ex["errors"], [])
	assert_eq(ex["paths"].size(), 3)
	assert_contains(a.reports.delete("zzz"), "[no_encontrado]")
	# el informe protege al combate guardado
	assert_contains(a.storage.remove_record("battles", bid), "[referenciado]")
	assert_eq(a.reports.delete(rid), "")
	assert_eq(a.reports.list().size(), 0)
	# informe de un lote guardado
	assert_true(a.batch.prepare({"mode": "duel", "reps": 4, "master_seed": 2, "a": {"path": FX + "attacker_a.json"}, "b": {"path": FX + "attacker_b.json"}})["ok"])
	a.batch.start(0)
	a.batch.finish()
	var lid: String = a.batch.save("Lote Y")["id"]
	var fromb := a.reports.from_batch(lid)
	assert_true(fromb["ok"], str(fromb))
	assert_eq(a.reports.verify(str(fromb["id"])), [], "verificado contra el lote guardado")
	assert_false(a.reports.from_batch("l9999")["ok"])


func test_rules_model_profiles_import_and_evaluation_and_settings() -> void:
	var a := _app()
	_import(a)
	assert_true(a.rules.rulesets().size() >= 1)
	assert_eq(a.rules.profiles().size(), 2)
	var pd := a.rules.profile_detail("builtin/reference_costs", "0.1.0")
	assert_true(pd["ok"] and pd["illustrative"] and pd["has_costs"])
	assert_contains(pd["notice"], "ILUSTRATIVO")
	assert_false(a.rules.profile_detail("builtin/technical_profile", "0.1.0")["has_costs"])
	assert_true(a.rules.ruleset_detail("builtin/default_ruleset", a.rules.rulesets()[0]["version"])["ok"])
	var ev := a.rules.evaluate("t/hero", "1.0.0", "builtin/reference_costs", "free", "standard")
	assert_almost(ev["creation_cost"], 30.0)
	var tech := a.rules.evaluate("t/hero", "1.0.0", "builtin/technical_profile", "free", "")
	assert_false(tech["evaluable"], "perfil sin costes: no evaluable")
	# importar un perfil con colision explicita
	var path := TMP + "/mi_perfil.json"
	var d: Dictionary = EntityFactory.load_json("res://content/balance/reference_costs.json")
	d["id"] = "mi_perfil"
	DirAccess.make_dir_recursive_absolute(TMP)
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string(JSON.stringify(d))
	f.close()
	assert_true(a.rules.import_file("profile", path, "user/mi_perfil", "1.0.0")["ok"])
	d["description"] = "otra"
	var f2 := FileAccess.open(path, FileAccess.WRITE)
	f2.store_string(JSON.stringify(d))
	f2.close()
	var col := a.rules.import_file("profile", path, "user/mi_perfil", "1.0.0")
	assert_false(col["ok"])
	assert_contains(col["error"], "[colision]")
	var nv := a.rules.import_file("profile", path, "user/mi_perfil", "1.0.0", "new_version")
	assert_true(nv["ok"])
	assert_eq(nv["version"], "1.0.1")
	assert_eq(a.rules.set_active_profile("user/mi_perfil"), [])
	assert_eq(a.profile().id, "mi_perfil")
	# ajustes persistentes y navegacion
	assert_eq(a.save_settings({"locale": "en"}), [])
	assert_eq(LocaleService.current(), "en")
	assert_eq(a.mode_label(), "Free mode")
	var a2 := AppController.new(a.storage.root)
	a2.boot()
	assert_eq(a2.settings()["locale"], "en", "los ajustes persisten")
	a.save_settings({"locale": "es"})
	assert_true(a.go("duel"))
	assert_true(a.go("viewer", {"x": 1}))
	assert_eq(a.screen, "viewer")
	assert_true(a.back())
	assert_eq(a.screen, "duel")
	assert_false(a.go("no_existe"))
	ContentLibrary._remove_tree(TMP)
