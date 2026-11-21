extends TestCase
## Fase 10 (plataformas): diagnostico de plataforma y conformidad multiplataforma, selector de archivos, ejemplos incluidos, garantia
## offline, filtros y presets de exportacion, y comprobaciones del APK/exportado si existen.

const TMP := "user://_tests_phase10"
var _n := 0


func _app() -> AppController:
	_n += 1
	var a := AppController.new("%s/p%d_%d" % [TMP, Time.get_ticks_usec(), _n])
	assert_eq(a.boot(), [])
	return a


func _tree_files(dir: String, exts: Array, out: Array) -> void:
	var d := DirAccess.open(dir)
	if d == null:
		return
	for sub in d.get_directories():
		if not str(sub).begins_with(".") and str(sub) != "build":
			_tree_files(dir.path_join(sub), exts, out)
	for f in d.get_files():
		if exts.has(str(f).get_extension().to_lower()):
			out.append(dir.path_join(f))


# --- diagnostico de plataforma ----------------------------------------------------------------------------------------------

func test_reference_platform_passes_the_conformance_battery() -> void:
	var pc := PlatformCheck.new({"skip_bench": true})
	var r := pc.run_all()
	assert_true(r["summary"]["compatible"], str(pc.checks.filter(func(c): return c["kind"] == "check" and not c["ok"])))
	assert_true(r["summary"]["passed"] >= 15)
	assert_eq(r["summary"]["failed"], 0)
	var names: Array = pc.checks.map(func(c): return c["name"])
	for want in ["math", "rng", "hashes", "formulas", "formats", "examples", "storage", "flow", "threads", "duel:simple", "duel:effects", "duel:script", "duel:summons", "duel:temporal_ai"]:
		assert_contains(names, want)
	assert_eq(pc.info["engine_version"], CombatEngine.ENGINE_VERSION)
	assert_true(pc.info.has("os") and pc.info.has("arch") and pc.info.has("godot"))
	assert_contains(pc.to_markdown(), "COMPATIBLE con la referencia")
	assert_true(pc.perf.is_empty(), "sin bancos si se omiten")


func test_expected_values_are_current_and_cover_every_scenario() -> void:
	var exp: Dictionary = EntityFactory.load_json(PlatformCheck.EXPECTED)
	var sc: Dictionary = EntityFactory.load_json(PlatformCheck.SCENARIOS)
	assert_eq(exp["engine_version"], CombatEngine.ENGINE_VERSION, "regenere con tools/gen_conformance.gd tras cambiar el motor")
	for s in sc["scenarios"]:
		assert_true(exp["duels"].has(s["id"]), "falta el esperado de %s" % s["id"])
		assert_eq(str(exp["duels"][s["id"]]["log_hash"]).length(), 64)
	assert_eq(exp["examples"].keys().size(), AppController.EXAMPLES.size())
	assert_true(exp["reference"]["os"] != "" and exp["reference"]["arch"] != "")
	# el escenario "simple" coincide con el combate de referencia del motor (golden de la fase 1)
	var golden: Dictionary = EntityFactory.load_json("res://tests/golden/duel_a_vs_b_seed42.json")
	assert_eq(golden["engine_version"], CombatEngine.ENGINE_VERSION)


func test_vectors_are_deterministic_and_incompatibilities_are_detected_and_reported() -> void:
	assert_eq(PlatformCheck.math_vectors(), PlatformCheck.math_vectors())
	assert_eq(PlatformCheck.rng_vectors(), PlatformCheck.rng_vectors())
	assert_eq(PlatformCheck.format_vectors(), PlatformCheck.format_vectors())
	assert_eq(PlatformCheck.hex_of(1.0), "000000000000f03f")
	assert_eq(PlatformCheck.hex_of(0.1 + 0.2), "343333333333d33f")
	# simular otra plataforma: un vector aritmetico y un duelo distintos
	var pc := PlatformCheck.new({"skip_bench": true})
	pc._expected["math"]["add"] = "0000000000000000"
	pc._expected["duels"]["simple"]["log_hash"] = "0".repeat(64)
	var r := pc.run_all()
	assert_false(r["summary"]["compatible"])
	assert_eq(r["summary"]["failed"], 2)
	var by := {}
	for c in pc.checks:
		by[c["name"]] = c
	assert_false(by["math"]["ok"])
	assert_contains(by["math"]["detail"], "1 de 22 vectores difieren")
	assert_eq(by["math"]["expected"][0]["vector"], "add")
	assert_false(by["duel:simple"]["ok"])
	assert_contains(by["duel:simple"]["detail"], "INCOMPATIBLE")
	assert_true(by["duel:effects"]["ok"], "el resto sigue bien")
	assert_contains(pc.to_markdown(), "INCOMPATIBILIDADES")
	# valores esperados ausentes o de otro motor: tampoco pasa en silencio
	var pc2 := PlatformCheck.new({"skip_bench": true})
	pc2._expected["engine_version"] = "0.0.1"
	pc2.run_all()
	assert_true(pc2.checks.filter(func(c): return str(c["name"]).begins_with("duel:") and not c["ok"] and str(c["detail"]).contains("regenere")).size() == 6)
	var pc3 := PlatformCheck.new({"skip_bench": true})
	pc3._expected = {}
	assert_false(pc3.run_all()["summary"]["compatible"])


func test_benchmarks_measure_throughput_without_scoring() -> void:
	var pc := PlatformCheck.new({"bench_ms": 150})
	while pc.step():
		pass
	assert_eq(pc.perf.size(), 3)
	for p in pc.perf:
		assert_true(p["duels"] >= 2 and p["duels_per_s"] > 0.0 and p["events_per_s"] > 0.0, str(p))
	assert_eq(pc.failed(), 0, "el rendimiento no puntua")
	for p in pc.perf:
		assert_true(p["target"] > 0.0, "hay objetivo provisional para %s" % p["scenario"])
		assert_eq(p["meets"], p["duels_per_s"] >= p["target"])
	assert_contains(pc.to_markdown(), "PROVISIONALES")
	assert_contains(pc.to_markdown(), "Duelos/s")


func test_performance_targets_are_provisional_external_and_consistent() -> void:
	var t: Dictionary = EntityFactory.load_json(PlatformCheck.TARGETS)
	assert_true(t["provisional"])
	var sc: Dictionary = EntityFactory.load_json(PlatformCheck.SCENARIOS)
	for klass in ["desktop", "mobile"]:
		for s in sc["scenarios"]:
			if ["simple", "effects", "summons"].has(s["id"]):
				assert_true(PlatformCheck.target_for(s["id"], klass) > 0.0, "%s/%s" % [klass, s["id"]])
	for id in ["simple", "effects", "summons"]:
		assert_true(PlatformCheck.target_for(id, "mobile") < PlatformCheck.target_for(id, "desktop"), "el movil exige menos")
	assert_eq(PlatformCheck.target_for("inexistente", "desktop"), 0.0)
	assert_eq(PlatformCheck.target_for("simple", "otra_clase"), 0.0)
	assert_true(["desktop", "mobile"].has(PlatformCheck.device_class()))


func test_platform_screen_runs_cooperatively_and_saves_the_report() -> void:
	var a := _app()
	var m: MainUI = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	m.app = a
	m.build_ui()
	a.go("platform")
	var ps := m.screen_node as PlatformScreen
	assert_true(ps != null)
	ps._start()
	var guard := 0
	while ps.running and guard < 100:
		ps._process(0.1)
		guard += 1
	assert_false(ps.running)
	assert_true(ps.pc.checks.size() >= 15)
	var txt := ""
	for l in ps.find_children("*", "Label", true, false):
		txt += (l as Label).text + "\n"
	assert_contains(txt, "COMPATIBLE con la referencia")
	var path := PlatformScreen.save_report(a, ps.pc)
	assert_true(FileAccess.file_exists(path))
	assert_true(FileAccess.file_exists(path.replace(".json", ".md")))
	assert_eq(JSON.parse_string(FileAccess.get_file_as_string(path))["schema"], "simhalla.platform_check/1")
	m.free()
	ContentLibrary._remove_tree(TMP)


# --- selector de archivos e importacion ------------------------------------------------------------------------------------------

func test_file_picker_strategies_classification_and_inbox() -> void:
	assert_eq(FilePicker.strategy(true, true), "native")
	assert_eq(FilePicker.strategy(true, false), "native")
	assert_eq(FilePicker.strategy(false, true), "inbox", "movil sin dialogo nativo: bandeja de entrada")
	assert_eq(FilePicker.strategy(false, false), "dialog", "escritorio: FileDialog de Godot")
	assert_true(["native", "dialog", "inbox"].has(FilePicker.strategy()))
	var root := "%s/pick%d" % [TMP, Time.get_ticks_usec()]
	var inbox := FilePicker.ensure_inbox(root)
	assert_true(DirAccess.dir_exists_absolute(inbox))
	assert_eq(FilePicker.list_inbox(root), [])
	# paquete como carpeta, zip, bundle, json y ruido
	DirAccess.make_dir_recursive_absolute(inbox.path_join("mi_paquete"))
	for f in {"mi_paquete/manifest.json": "{}", "otro.zip": "x", "dia.simbundle": "x", "datos.json": "{}", "notas.txt": "x", ".oculto.zip": "x"}:
		DirAccess.make_dir_recursive_absolute(inbox.path_join(f).get_base_dir())
		var h := FileAccess.open(inbox.path_join(f), FileAccess.WRITE)
		h.store_string(str({"mi_paquete/manifest.json": "{}"}.get(f, "x")))
		h.close()
	DirAccess.make_dir_recursive_absolute(inbox.path_join("carpeta_sin_manifiesto"))
	var items := FilePicker.list_inbox(root)
	var kinds := {}
	for it in items:
		kinds[it["name"]] = it["kind"]
	assert_eq(kinds["mi_paquete"], "package")
	assert_eq(kinds["otro.zip"], "package")
	assert_eq(kinds["dia.simbundle"], "bundle")
	assert_eq(kinds["datos.json"], "json")
	assert_false(kinds.has("notas.txt"))
	assert_false(kinds.has("carpeta_sin_manifiesto"))
	assert_eq(FilePicker.classify("x.SIMPKG"), "package", "extension insensible a mayusculas")
	assert_eq(FilePicker.classify("x.exe"), "unknown")
	# copiar a la bandeja
	var src := "%s/ajeno.simbundle" % TMP
	DirAccess.make_dir_recursive_absolute(TMP)
	var f2 := FileAccess.open(src, FileAccess.WRITE)
	f2.store_string("datos")
	f2.close()
	var cp := FilePicker.copy_into_inbox(src, root)
	assert_true(cp["ok"])
	assert_true(FileAccess.file_exists(cp["path"]))
	assert_false(FilePicker.copy_into_inbox("%s/nada.zip" % TMP, root)["ok"])
	assert_false(FilePicker.copy_into_inbox(src.get_base_dir().path_join("x.exe"), root)["ok"])
	ContentLibrary._remove_tree(TMP)


func test_import_screen_inbox_bundle_and_picker_fallback() -> void:
	var a := _app()
	var m: MainUI = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	m.app = a
	m.build_ui()
	# paquete en la bandeja -> aparece en la lista -> se valida al pulsarlo
	var inbox := FilePicker.ensure_inbox(a.storage.root)
	DirAccess.make_dir_recursive_absolute(inbox.path_join("heroe"))
	for rel in {"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": "t/heroe", "version": "1.0.0", "type": "character", "name": "H"}),
			"character.json": JSON.stringify({"schema": "simhalla.character/1", "name": "H", "stats": {"ATK": 130}, "basic_attack": true})}:
		var f := FileAccess.open(inbox.path_join("heroe").path_join(rel), FileAccess.WRITE)
		f.store_string({"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": "t/heroe", "version": "1.0.0", "type": "character", "name": "H"}),
			"character.json": JSON.stringify({"schema": "simhalla.character/1", "name": "H", "stats": {"ATK": 130}, "basic_attack": true})}[rel])
		f.close()
	a.go("import")
	var b := m.find_child("inbox_heroe", true, false) as Button
	assert_true(b != null, "la bandeja lista el paquete")
	b.pressed.emit()
	assert_true((m.find_child("import_btn", true, false)) != null, "tras pulsarlo se valida y se puede importar")
	(m.find_child("import_btn", true, false) as Button).pressed.emit()
	assert_true(a.storage.library.has("t/heroe", "1.0.0"))
	# bundle portable importado desde la interfaz
	var run := a.duel
	run.add_package("t/heroe")
	run.add_file("res://content/fixtures/entities/attacker_b.json")
	var vm: ViewerModel = run.start()["viewer"]
	var bid: String = vm.save("Para bundle", false)["id"]
	var bpath := a.storage.root.path_join("exports/b.simbundle")
	assert_true(BundleIO.export_records(a.storage, [{"store": "battles", "id": bid}], bpath)["ok"])
	var other := _app()
	var m2: MainUI = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	m2.app = other
	m2.build_ui()
	other.go("import")
	(m2.find_child("path_edit", true, false) as LineEdit).text = bpath
	(m2.find_child("validate_btn", true, false) as Button).pressed.emit()
	assert_true(other.storage.library.has("t/heroe", "1.0.0"), "el bundle trae sus paquetes")
	assert_eq(other.storage.battles.list().size(), 1)
	var txt := ""
	for l in m2.screen_node.find_children("*", "Label", true, false):
		txt += (l as Label).text + "\n"
	assert_contains(txt, "Paquete portable importado: 1 paquetes, 1 registros")
	# en un dispositivo sin selector, "Examinar" informa de la bandeja
	assert_true((m.find_child("browse_btn", true, false)) != null)
	m.free()
	m2.free()
	ContentLibrary._remove_tree(TMP)


func test_bundled_examples_install_idempotently_and_work() -> void:
	var a := _app()
	a.go("library")
	var m: MainUI = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	m.app = a
	m.build_ui()
	var btn := m.find_child("install_examples_btn", true, false) as Button
	assert_true(btn != null, "biblioteca vacia: boton de ejemplos")
	btn.pressed.emit()
	assert_eq(a.library.entries().size(), AppController.EXAMPLES.size())
	var again := a.install_examples()
	assert_eq(again["installed"], [])
	assert_eq(again["present"].size(), 6)
	assert_eq(again["errors"], [])
	for e in a.library.entries():
		assert_true(e["valid"], e["id"])
	# un duelo con los ejemplos instalados
	a.duel.reset()
	a.duel.add_package("examples/arcane_duelist")
	a.duel.add_package("examples/iron_vanguard")
	var v := a.duel.validate()
	assert_true(v["can_start"], str(v["errors"]))
	var vm: ViewerModel = a.duel.start()["viewer"]
	vm.to_end()
	assert_true(vm.session.result().is_win() or vm.session.result().is_draw())
	m.free()
	ContentLibrary._remove_tree(TMP)


# --- offline, licencias y exportacion ------------------------------------------------------------------------------------------------

func test_application_code_has_no_network_or_host_access() -> void:
	var files: Array = []
	_tree_files("res://src", ["gd"], files)
	_tree_files("res://tools", ["gd"], files)
	assert_true(files.size() > 100)
	var banned := ["HTTPRequest", "HTTPClient", "WebSocketPeer", "StreamPeerTCP", "TCPServer", "UDPServer", "PacketPeerUDP", "ENetMultiplayer", "WebRTC",
		"OS.shell_open", "OS.execute", "OS.create_process", "JavaScriptBridge", "OS.kill", "Engine.register_singleton", "OS.set_environment"]
	for f in files:
		var text := FileAccess.get_file_as_string(f)
		for b in banned:
			assert_false(text.contains(b), "%s usa %s" % [f, b])
	# gratuidad: sin recursos de terceros en el repositorio (imagenes/fuentes)
	var assets: Array = []
	_tree_files("res://", ["png", "jpg", "jpeg", "webp", "svg", "ttf", "otf", "woff", "woff2", "ogg", "wav", "mp3"], assets)
	assert_eq(assets, [], "no hay activos de terceros que atribuir")


func test_export_presets_include_needed_files_exclude_dev_files_and_request_no_permissions() -> void:
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	var seen := {}
	for sec in cfg.get_sections():
		if sec.ends_with(".options"):
			continue
		var name := str(cfg.get_value(sec, "name"))
		seen[name] = sec
		var inc := str(cfg.get_value(sec, "include_filter"))
		var exc := str(cfg.get_value(sec, "exclude_filter"))
		for ext in ["*.json", "*.sim", "*.md"]:
			assert_contains(inc, ext, "%s debe incluir %s (paquetes, esquemas, localizacion, scripts)" % [name, ext])
		for dev in ["tests/*", "tools/*", "docs/*"]:
			assert_contains(exc, dev, "%s debe excluir %s" % [name, dev])
	assert_true(seen.has("Android") and seen.has("Linux"))
	var ao := str(seen["Android"]) + ".options"
	assert_true(cfg.get_value(ao, "architectures/arm64-v8a"))
	assert_false(cfg.get_value(ao, "architectures/armeabi-v7a"))
	assert_true(str(cfg.get_value(ao, "package/unique_name")).begins_with("com."))
	for k in cfg.get_section_keys(ao):
		if str(k).begins_with("permissions/"):
			assert_false(bool(cfg.get_value(ao, k)), "el preset de Android no debe pedir %s" % k)
	assert_true(FileAccess.file_exists("res://docs/LICENSES.md"))
	assert_contains(FileAccess.get_file_as_string("res://docs/LICENSES.md"), "MIT")
	assert_eq(ProjectSettings.get_setting("application/run/main_scene"), "res://src/ui/main.tscn")
	assert_eq(ProjectSettings.get_setting("display/window/stretch/mode"), "canvas_items")
	assert_eq(ProjectSettings.get_setting("display/window/stretch/aspect"), "expand")


func test_exported_apk_if_present_has_no_permissions_and_arm64_only() -> void:
	var path := ProjectSettings.globalize_path("res://build/simhalla-debug.apk")
	if not FileAccess.file_exists(path):
		return
	var z := ZIPReader.new()
	assert_eq(z.open(path), OK)
	var names := z.get_files()
	assert_true(names.has("AndroidManifest.xml"))
	assert_true(names.has("lib/arm64-v8a/libgodot_android.so"))
	for n in names:
		if str(n).begins_with("lib/"):
			assert_true(str(n).begins_with("lib/arm64-v8a/"), "solo arm64: %s" % n)
	var man := z.read_file("AndroidManifest.xml")
	var txt8 := man.get_string_from_ascii()
	var u16 := PackedByteArray()
	for ch in "permission.INTERNET".to_utf8_buffer():
		u16.append(ch)
		u16.append(0)
	assert_false(txt8.contains("permission.INTERNET") or man.hex_encode().contains(u16.hex_encode()), "el APK no pide INTERNET (offline)")
	for need in ["assets/content/locale/es.json", "assets/content/conformance/expected.json", "assets/schemas/ai.schema.json", "assets/content/packages/rune_caster/scripts/chain.sim"]:
		assert_true(names.has(need), "el APK incluye %s" % need)
	for dev in names:
		assert_false(str(dev).begins_with("assets/tests/") or str(dev).begins_with("assets/tools/") or str(dev).begins_with("assets/docs/"), "el APK no incluye archivos de desarrollo")
	z.close()
