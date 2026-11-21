extends TestCase
## Fase 9 (almacenamiento): elementos versionados inmutables, registros con indice, combates guardados reproducibles,
## referencias y borrado protegido, informes guardados y verificables, bundles portables.

const TMP := "user://_tests_phase9"
const FX := "res://content/fixtures/entities/"
var _n := 0


func _store() -> AppStorage:
	_n += 1
	var s := AppStorage.new("%s/s%d_%d" % [TMP, Time.get_ticks_usec(), _n])
	assert_eq(s.install_builtins(), [])
	return s


func _pkg(stats: Dictionary, id: String = "t/hero", version: String = "1.0.0", extra_char: Dictionary = {}) -> String:
	var d := "%s/pkg%d_%d" % [TMP, Time.get_ticks_usec(), _n]
	_n += 1
	var ch := {"schema": "simhalla.character/1", "name": "Hero", "stats": stats, "basic_attack": true}
	ch.merge(extra_char, true)
	var files := {"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": id, "version": version, "type": "character", "name": "Hero " + version}),
		"character.json": JSON.stringify(ch)}
	for rel in files:
		DirAccess.make_dir_recursive_absolute(d)
		var f := FileAccess.open(d.path_join(rel), FileAccess.WRITE)
		f.store_string(files[rel])
		f.close()
	return d


func _import(s: AppStorage, stats: Dictionary, id: String = "t/hero", version: String = "1.0.0") -> void:
	var rep := PackageImporter.new(s.library).import_package(_pkg(stats, id, version))
	assert_true(rep.ok(), "\n".join(rep.errors))


func _duel_cfg(pkg_a: String = "t/hero", constraint: String = "*") -> Dictionary:
	return {"seed": 12345678901234567, "entities": [
		{"package": pkg_a, "version": constraint, "overrides": {"id": "a", "team": "A"}},
		{"path": FX + "attacker_b.json", "overrides": {"id": "b", "team": "B"}}]}


func _run_pinned(s: AppStorage, cfg: Dictionary) -> Array:
	var pin := s.pin_config(cfg)
	assert_true(pin["ok"], str(pin["errors"]))
	var o := SimulationSession.open(pin["config"])
	assert_true(o["ok"], str(o["errors"]))
	var sess: SimulationSession = o["session"]
	sess.run_to_end()
	return [sess, pin]


# --- elementos versionados --------------------------------------------------------------------------------------------------

func test_versioned_store_is_immutable_and_explicit_about_collisions() -> void:
	var s := _store()
	var st := s.rulesets
	assert_true(st.has("builtin/default_ruleset", "0.1.0-provisional") or st.list().size() >= 1)
	var base := {"damage": {"rounding": {"mode": "round", "decimals": 0}}}
	var r1 := st.put("t/mi_regla", "1.0.0", base)
	assert_true(r1["ok"] and r1["status"] == "stored")
	assert_eq(st.put("t/mi_regla", "1.0.0", base)["status"], "already_present", "idempotente")
	var changed := {"damage": {"rounding": {"mode": "floor", "decimals": 0}}}
	var col := st.put("t/mi_regla", "1.0.0", changed)
	assert_false(col["ok"])
	assert_contains(col["error"], "[colision]")
	assert_eq(VersionedStore.canonical_hash(st.get_item("t/mi_regla", "1.0.0")["data"]), VersionedStore.canonical_hash(base), "lo existente no se sobrescribe")
	var nv := st.put_resolving("t/mi_regla", "1.0.0", changed)
	assert_true(nv["ok"])
	assert_eq(nv["version"], "1.0.1", "version nueva explicita")
	assert_eq(st.versions("t/mi_regla"), ["1.0.0", "1.0.1"])
	assert_eq(st.resolve("t/mi_regla", "^1.0.0")["version"], "1.0.1")
	assert_eq(st.resolve("t/mi_regla", "1.0.0")["version"], "1.0.0")
	# validacion e ids
	assert_contains(st.put("t/mala", "1.0.0", {"damage": {"rounding": {"mode": "magico"}}})["error"], "[validacion]")
	assert_contains(st.put("Mal Id", "1.0.0", base)["error"], "[id]")
	assert_contains(st.put("t/x", "uno", base)["error"], "[version]")
	# manipulacion en disco
	var f := FileAccess.open(st.root.path_join("t/mi_regla/1.0.0/data.json"), FileAccess.WRITE)
	f.store_string("{\"damage\": {\"rounding\": {\"mode\": \"ceil\"}}}")
	f.close()
	assert_contains(st.get_item("t/mi_regla", "1.0.0")["error"], "[integridad]")
	assert_eq(st.remove("t/mi_regla", "1.0.1"), "")
	assert_eq(st.versions("t/mi_regla"), ["1.0.0"])


func test_builtins_settings_and_configs() -> void:
	var s := _store()
	assert_true(s.rulesets.list().size() >= 1)
	assert_eq(s.profiles.list().size(), 2)
	assert_true(s.profiles.resolve("builtin/reference_costs", "*").size() > 0)
	assert_eq(s.install_builtins(), [], "idempotente")
	assert_eq(s.settings()["locale"], "es")
	assert_eq(s.save_settings({"locale": "en", "workers": 2, "default_mode": "regulated"}), [])
	var st := s.settings()
	assert_eq(st["locale"], "en")
	assert_eq(int(st["workers"]), 2)
	assert_eq(st["history"], "summary", "el resto conserva su valor")
	for bad in [{"locale": "xx"}, {"workers": 99}, {"default_mode": "x"}, {"history": "x"}, {"magia": 1}]:
		assert_true(s.save_settings(bad).size() > 0, str(bad))
	# configuraciones de simulacion guardadas y versionadas
	var duel := {"kind": "duel", "config": _duel_cfg()}
	assert_true(s.configs.put("t/duelo_base", "1.0.0", duel)["ok"])
	assert_false(s.configs.put("t/malo", "1.0.0", {"kind": "otro"})["ok"])
	assert_false(s.configs.put("t/lote_malo", "1.0.0", {"kind": "batch", "config": {"scenarios": []}})["ok"])


# --- registros --------------------------------------------------------------------------------------------------------------------

func test_record_store_index_history_integrity_and_references() -> void:
	var s := _store()
	var rs := s.reports
	var a := rs.add("Informe uno", {"report.json": "{\"a\":1}", "report.md": "# uno"}, [{"kind": "battle", "id": "b0001"}], {"x": 1})
	var b := rs.add("Informe dos", {"report.json": "{\"a\":2}"}, [], {})
	assert_true(a["ok"] and b["ok"])
	assert_eq(a["id"], "r0001")
	assert_eq(b["id"], "r0002", "ids secuenciales sin reloj")
	assert_eq(rs.list().size(), 2)
	assert_eq(rs.list({"query": "DOS"}).size(), 1)
	assert_eq(rs.list({"ref_id": "b0001"}).size(), 1)
	assert_eq(rs.read_json("r0001", "report.json"), {"a": 1.0})
	assert_eq(rs.read_text("r0001", "report.md"), "# uno")
	assert_eq(rs.verify("r0001"), "")
	assert_true(rs.entry("r0001")["meta"].has("saved_at"), "instante informativo")
	var f := FileAccess.open(rs.root.path_join("r0001/report.md"), FileAccess.WRITE)
	f.store_string("# alterado")
	f.close()
	assert_contains(rs.verify("r0001"), "[integridad]")
	assert_contains(rs.add("x", {"../fuera": "x"})["error"], "[nombre]")
	assert_eq(rs.remove("r0002"), "")
	assert_eq(rs.list().size(), 1)
	assert_eq(rs.add("tras borrar", {"report.json": "{}"})["id"], "r0003", "los ids no se reutilizan")
	assert_contains(rs.remove("zzz"), "[no_encontrado]")
	# el indice persiste (nueva instancia sobre el mismo directorio)
	assert_eq(RecordStore.new(rs.root, "r", "report").list().size(), 2)


# --- combates guardados -------------------------------------------------------------------------------------------------------------

func test_saved_battle_pins_exact_content_and_replays_identically() -> void:
	var s := _store()
	_import(s, {"ATK": 150})
	var run := _run_pinned(s, _duel_cfg())
	var sess: SimulationSession = run[0]
	var pin: Dictionary = run[1]
	var spec: Dictionary = pin["config"]["entities"][0]
	assert_eq(spec["version"], "1.0.0", "la restriccion se fija a la version exacta")
	assert_eq(spec["hash"].length(), 64)
	assert_true(pin["config"]["entities"][1].has("data"), "entidad suelta inline")
	assert_true(pin["config"].has("ruleset_data") and pin["config"].has("profile_data"))
	assert_eq(pin["config"]["seed"], "12345678901234567", "semilla de 64 bits como texto")
	var sv := s.save_battle(sess, pin["config"], {"title": "Duelo de prueba", "with_trace": true})
	assert_true(sv["ok"], str(sv))
	assert_eq(s.battles.list().size(), 1)
	assert_eq(s.battles.entry(sv["id"])["refs"][0]["kind"], "package")
	assert_true(s.battles.entry(sv["id"])["files"].has("trace.json"))
	var rp := s.replay_battle(sv["id"])
	assert_true(rp["ok"], str(rp["errors"]))
	assert_true(rp["matches"], "el combate guardado se reproduce con el mismo log_hash")
	assert_eq(rp["warnings"], [])
	assert_eq((rp["session"] as SimulationSession).run_to_end().log_hash, sess.result().log_hash)
	# el registro no es un combate sin terminar
	var open_s := SimulationSession.open(pin["config"])["session"] as SimulationSession
	assert_false(s.save_battle(open_s, pin["config"])["ok"])
	# alterar el registro en disco se detecta
	var f := FileAccess.open(s.battles.root.path_join(sv["id"] + "/record.json"), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	assert_false(s.replay_battle(sv["id"])["ok"])


func test_new_package_version_does_not_change_old_saved_battles() -> void:
	var s := _store()
	_import(s, {"ATK": 150}, "t/hero", "1.0.0")
	var run := _run_pinned(s, _duel_cfg("t/hero", "*"))
	var id: String = s.save_battle(run[0], run[1]["config"], {})["id"]
	var h1: String = (run[0] as SimulationSession).result().log_hash
	_import(s, {"ATK": 900}, "t/hero", "1.1.0")
	assert_eq(s.library.resolve("t/hero", "*")["version"], "1.1.0", "ahora hay una version mas nueva")
	var rp := s.replay_battle(id)
	assert_true(rp["ok"] and rp["matches"], "el combate antiguo sigue usando la 1.0.0 fijada")
	assert_eq((rp["session"] as SimulationSession).run_to_end().log_hash, h1)
	# un duelo NUEVO con '*' usa la 1.1.0 y da otro resultado
	var run2 := _run_pinned(s, _duel_cfg("t/hero", "*"))
	assert_eq(run2[1]["config"]["entities"][0]["version"], "1.1.0")
	assert_ne((run2[0] as SimulationSession).result().log_hash, h1)
	# la huella fijada impide reproducir en silencio con contenido alterado
	var cfg: Dictionary = (run[1]["config"] as Dictionary).duplicate(true)
	cfg["entities"][0]["hash"] = "0".repeat(64)
	assert_contains(" ".join(DuelRunner.build_engine(cfg)["errors"]), "[contenido_alterado]")


func test_remove_package_is_refused_while_saved_records_reference_it() -> void:
	var s := _store()
	_import(s, {"ATK": 150}, "t/hero", "1.0.0")
	_import(s, {"ATK": 160}, "t/hero", "1.1.0")
	var run := _run_pinned(s, _duel_cfg("t/hero", "1.0.0"))
	var bid: String = s.save_battle(run[0], run[1]["config"], {})["id"]
	var refs := s.references_to("package", "t/hero", "1.0.0")
	assert_eq(refs.size(), 1)
	assert_eq(refs[0]["id"], bid)
	assert_contains(s.remove_package("t/hero", "1.0.0"), "[referenciado]")
	assert_true(s.library.has("t/hero", "1.0.0"), "no se borro")
	assert_eq(s.remove_package("t/hero", "1.1.0"), "", "la version sin referencias si se puede borrar")
	# un informe que referencia el combate protege al combate
	var m: Dictionary = IndividualReport.build((run[0] as SimulationSession).engine, {"config": run[1]["config"]})["report"]
	var rep := s.save_report(m, "Informe del duelo", [{"kind": "battle", "id": bid}])
	assert_true(rep["ok"])
	assert_contains(s.remove_record("battles", bid), "[referenciado]")
	assert_eq(s.remove_record("reports", rep["id"]), "")
	assert_eq(s.remove_record("battles", bid), "")
	assert_eq(s.remove_package("t/hero", "1.0.0"), "", "sin registros dependientes ya se puede")
	assert_contains(s.remove_record("magia", "x"), "[almacen]")


# --- informes y lotes ---------------------------------------------------------------------------------------------------------------

func test_reports_are_saved_in_three_formats_and_verifiable() -> void:
	var s := _store()
	_import(s, {"ATK": 150})
	var run := _run_pinned(s, _duel_cfg())
	var m: Dictionary = IndividualReport.build((run[0] as SimulationSession).engine, {"config": run[1]["config"]})["report"]
	var sv := s.save_report(m, "Informe individual", [])
	assert_true(sv["ok"])
	var e := s.reports.entry(sv["id"])
	assert_eq(e["files"].size(), 3)
	assert_eq(e["meta"]["report_kind"], "individual")
	assert_eq(e["meta"]["content_hash"], ReportExporter.content_hash(m))
	assert_eq(s.verify_report(sv["id"]), [])
	assert_contains(s.reports.read_text(sv["id"], "report.html"), "<!doctype html>")
	# alterar el JSON guardado: la verificacion lo detecta
	var f := FileAccess.open(s.reports.root.path_join(sv["id"] + "/report.json"), FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	assert_true(s.verify_report(sv["id"]).size() > 0)


func test_batches_are_stored_and_reports_rebuild_from_stored_records() -> void:
	var s := _store()
	var cfg := BatchModes.duel({"path": FX + "attacker_a.json"}, {"path": FX + "attacker_b.json"}, 8, 99999999999999999,
		{"ruleset_overrides": {"victory": {"limits": {"max_turns": 60, "stagnation_turns": 30}}}}, "A", "B")
	var plan: BatchPlan = BatchPlan.from_dict(cfg)["plan"]
	var res := BatchRunner.new(plan, {}).wait()
	var sv := s.save_batch(res, "Lote de prueba")
	assert_true(sv["ok"], str(sv))
	var lb := s.load_batch(sv["id"])
	assert_true(lb["ok"], str(lb["error"]))
	var back: BatchResult = lb["result"]
	assert_eq(back.fingerprint, res.fingerprint)
	assert_eq(back.executed, res.executed)
	for i in res.records.size():
		assert_eq(back.records[i]["seed"], res.records[i]["seed"], "semilla de 64 bits exacta tras guardar")
		assert_eq(back.records[i]["log_hash"], res.records[i]["log_hash"])
	assert_eq(BatchResult.compute_fingerprint(back.engine_version, back.plan_fingerprint, back.records), res.fingerprint, "la huella se recalcula igual")
	var m := BatchReport.build(back)
	var m0 := BatchReport.build(res)
	assert_eq(ReportExporter.content_hash(m), ReportExporter.content_hash(m0), "informe identico desde el lote guardado")
	var rid: String = s.save_report(m, "Informe del lote", [{"kind": "batch", "id": sv["id"]}])["id"]
	assert_eq(s.verify_report(rid), [], "verificado contra los registros del lote guardado")
	assert_contains(s.remove_record("batches", sv["id"]), "[referenciado]")


# --- bundles portables ---------------------------------------------------------------------------------------------------------------

func test_portable_bundle_moves_a_battle_with_its_exact_packages() -> void:
	var a := _store()
	_import(a, {"ATK": 150}, "t/hero", "1.0.0")
	var run := _run_pinned(a, _duel_cfg("t/hero", "1.0.0"))
	var bid: String = a.save_battle(run[0], run[1]["config"], {"title": "Para exportar"})["id"]
	var m: Dictionary = IndividualReport.build((run[0] as SimulationSession).engine, {"config": run[1]["config"]})["report"]
	var rid: String = a.save_report(m, "Informe", [{"kind": "battle", "id": bid}])["id"]
	var path := TMP + "/portable/duelo.simbundle"
	var ex := BundleIO.export_records(a, [{"store": "battles", "id": bid}, {"store": "reports", "id": rid}], path)
	assert_true(ex["ok"], str(ex["errors"]))
	assert_eq(ex["packages"], 1)
	assert_eq(ex["records"], 2)
	# otro dispositivo (almacen vacio)
	var b := _store()
	assert_eq(b.library.list().size(), 0)
	var im := BundleIO.import_bundle(b, path)
	assert_true(im["ok"], str(im["errors"]))
	assert_eq(im["packages"], ["t/hero@1.0.0"])
	assert_eq(im["records"].size(), 2)
	assert_true(b.library.has("t/hero", "1.0.0"))
	var new_b: String = ""
	var new_r: String = ""
	for r in im["records"]:
		if r["store"] == "battles":
			new_b = r["new_id"]
		else:
			new_r = r["new_id"]
	assert_eq(b.battles.entry(new_b)["meta"]["imported_from"], bid)
	assert_eq(b.reports.entry(new_r)["refs"][0]["id"], new_b, "las referencias entre registros se remapean")
	var rp := b.replay_battle(new_b)
	assert_true(rp["ok"] and rp["matches"], "el combate importado se reproduce igual en el otro almacen")
	assert_eq(b.verify_report(new_r), [])
	# importar de nuevo: paquetes idempotentes, registros nuevos
	var again := BundleIO.import_bundle(b, path)
	assert_true(again["ok"])
	assert_eq(b.battles.list().size(), 2)
	# conflicto explicito: otra version distinta con el mismo id@version
	var c := _store()
	_import(c, {"ATK": 999}, "t/hero", "1.0.0")
	var conflict := BundleIO.import_bundle(c, path)
	assert_false(conflict["ok"])
	assert_contains(" ".join(conflict["errors"]), "version_conflicto")
	assert_eq(c.battles.list().size(), 0, "un conflicto no importa nada")
	assert_eq(c.library.entry("t/hero", "1.0.0")["hash"], c.library.resolve("t/hero", "1.0.0")["hash"], "lo existente intacto")


func test_bundle_import_rejects_tampered_or_malformed_bundles() -> void:
	var a := _store()
	_import(a, {"ATK": 150})
	var run := _run_pinned(a, _duel_cfg())
	var bid: String = a.save_battle(run[0], run[1]["config"], {})["id"]
	var path := TMP + "/portable/ok.simbundle"
	assert_true(BundleIO.export_records(a, [{"store": "battles", "id": bid}], path)["ok"])
	var b := _store()
	# archivo alterado dentro del ZIP
	var rd := PackageSource._read_zip(path)
	var files: Dictionary = rd["files"]
	var tampered := TMP + "/portable/tampered.simbundle"
	var z := ZIPPacker.new()
	z.open(tampered)
	for n in files:
		z.start_file(str(n))
		var bytes: PackedByteArray = files[n]
		if str(n).ends_with("record.json"):
			bytes = "{\"manipulado\": true}".to_utf8_buffer()
		z.write_file(bytes)
		z.close_file()
	z.close()
	var r1 := BundleIO.import_bundle(b, tampered)
	assert_false(r1["ok"])
	assert_contains(" ".join(r1["errors"]), "[integridad]")
	assert_eq(b.battles.list().size(), 0)
	# sin manifiesto / no es un zip / schema distinto
	var nz := TMP + "/portable/nozip.simbundle"
	var f := FileAccess.open(nz, FileAccess.WRITE)
	f.store_string("no soy un zip")
	f.close()
	assert_false(BundleIO.import_bundle(b, nz)["ok"])
	var empty := TMP + "/portable/vacio.simbundle"
	var z2 := ZIPPacker.new()
	z2.open(empty)
	z2.start_file("otro.txt")
	z2.write_file("x".to_utf8_buffer())
	z2.close_file()
	z2.close()
	assert_contains(" ".join(BundleIO.import_bundle(b, empty)["errors"]), "bundle.json")
	var traversal := TMP + "/portable/trav.simbundle"
	var z3 := ZIPPacker.new()
	z3.open(traversal)
	z3.start_file("../fuera.txt")
	z3.write_file("x".to_utf8_buffer())
	z3.close_file()
	z3.close()
	assert_false(BundleIO.import_bundle(b, traversal)["ok"], "rutas peligrosas rechazadas")
	assert_false(BundleIO.export_records(a, [{"store": "battles", "id": "b9999"}], TMP + "/portable/x.simbundle")["ok"])
	assert_false(BundleIO.export_records(a, [{"store": "magia", "id": "x"}], TMP + "/portable/x.simbundle")["ok"])
	ContentLibrary._remove_tree(TMP)
