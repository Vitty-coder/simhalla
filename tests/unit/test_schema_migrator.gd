extends TestCase
## Migraciones de esquema: cadena de pasos, version futura, paso ausente, pureza, y lectores conectados (con migrador compartido restaurado).

const TMP := "user://_tests_migr"


func _fresh() -> SchemaMigrator:
	var m := SchemaMigrator.new()
	m.set_current("settings", 3)
	m.register("settings", 1, func(d: Dictionary) -> Dictionary:
		d["workers"] = int(d.get("hilos", 0))
		d.erase("hilos")
		return d)
	m.register("settings", 2, func(d: Dictionary) -> Dictionary:
		d["locale"] = str(d.get("idioma", "es"))
		d.erase("idioma")
		return d)
	return m


func test_parse_id() -> void:
	assert_eq(SchemaMigrator.parse_id("simhalla.settings/2"), {"ok": true, "family": "settings", "version": 2})
	for bad in ["settings/1", "simhalla./1", "simhalla.x/0", "simhalla.x/a", "simhalla.x/1/2", "otro.x/1", 5, null]:
		assert_false(SchemaMigrator.parse_id(bad)["ok"], str(bad))


func test_chain_applies_every_step_in_order_without_mutating_the_input() -> void:
	var m := _fresh()
	var orig := {"schema": "simhalla.settings/1", "hilos": 4, "idioma": "en"}
	var r := m.migrate(orig)
	assert_true(r["ok"])
	assert_true(r["migrated"])
	assert_eq([r["from"], r["to"]], [1, 3])
	assert_eq(r["data"], {"schema": "simhalla.settings/3", "workers": 4, "locale": "en"})
	assert_eq(orig, {"schema": "simhalla.settings/1", "hilos": 4, "idioma": "en"}, "el original no cambia")
	var r2 := m.migrate({"schema": "simhalla.settings/2", "idioma": "en"})
	assert_eq(r2["data"], {"schema": "simhalla.settings/3", "locale": "en"}, "solo los pasos pendientes")


func test_current_unknown_and_schemaless_data_are_untouched() -> void:
	var m := _fresh()
	var cur := {"schema": "simhalla.settings/3", "workers": 1}
	var r := m.migrate(cur)
	assert_true(r["ok"] and not r["migrated"])
	assert_eq(r["data"], cur)
	assert_false(m.migrate({"x": 1})["migrated"])
	assert_true(m.migrate({"schema": "simhalla.inventada/9"})["ok"], "familia desconocida: no es asunto del migrador")
	assert_true(m.migrate({"schema": "texto raro"})["ok"])
	assert_true(SchemaMigrator.new().migrate({"schema": "simhalla.manifest/1"})["ok"], "todas las familias conocidas estan en /1")


func test_future_version_and_missing_or_broken_step_are_explicit_errors() -> void:
	var m := _fresh()
	var f := m.migrate({"schema": "simhalla.settings/4"})
	assert_false(f["ok"])
	assert_contains(f["errors"][0], "[schema_futuro]")
	var gap := SchemaMigrator.new()
	gap.set_current("ai", 3)
	gap.register("ai", 2, func(d): return d)
	var g := gap.migrate({"schema": "simhalla.ai/1"})
	assert_false(g["ok"])
	assert_contains(g["errors"][0], "[migracion_ausente]")
	assert_contains(g["errors"][0], "ai/1 a ai/2")
	var bad := SchemaMigrator.new()
	bad.set_current("ai", 2)
	bad.register("ai", 1, func(d): return null)
	assert_contains(bad.migrate({"schema": "simhalla.ai/1"})["errors"][0], "[migracion_fallida]")
	assert_eq(m.upgraded({"schema": "simhalla.settings/4"}), {"schema": "simhalla.settings/4"}, "upgraded devuelve el original si no se puede")
	assert_eq(m.upgraded([1]), [1])


func test_readers_use_the_shared_migrator() -> void:
	var shared := SchemaMigrator.default()
	var old_cur: Dictionary = shared.current.duplicate()
	var old_steps: Dictionary = shared.steps.duplicate(true)
	var root := "%s/r%d" % [TMP, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(root)
	var st := AppStorage.new(root)
	# ajustes: formato antiguo -> se leen migrados
	shared.set_current("settings", 2)
	shared.register("settings", 1, func(d: Dictionary) -> Dictionary:
		d["locale"] = str(d.get("idioma", "es"))
		d.erase("idioma")
		return d)
	var f := FileAccess.open(root.path_join("settings.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema": "simhalla.settings/1", "idioma": "en", "workers": 2}))
	f.close()
	var s := st.settings()
	assert_eq(s["locale"], "en")
	assert_eq(int(s["workers"]), 2)
	# ajustes de una version futura: se ignoran (valores por defecto), nunca se interpretan a medias
	f = FileAccess.open(root.path_join("settings.json"), FileAccess.WRITE)
	f.store_string(JSON.stringify({"schema": "simhalla.settings/9", "locale": "en"}))
	f.close()
	assert_eq(st.settings()["locale"], AppStorage.DEFAULT_SETTINGS["locale"])
	# manifiesto de bundle de una version futura: rechazo explicito
	shared.set_current("bundle", 1)
	var zp := root.path_join("b.simbundle")
	var z := ZIPPacker.new()
	z.open(zp)
	z.start_file("bundle.json")
	z.write_file(JSON.stringify({"schema": "simhalla.bundle/2", "items": [], "packages": [], "hashes": {}}).to_utf8_buffer())
	z.close_file()
	z.close()
	var im := BundleIO.import_bundle(st, zp)
	assert_false(im["ok"])
	assert_contains(im["errors"][0], "[schema_futuro]")
	# importador: el dato migrado se usa y se avisa (sin tocar los bytes originales, luego la huella no cambia)
	shared.set_current("character", 2)
	shared.register("character", 1, func(d: Dictionary) -> Dictionary:
		d["name"] = str(d.get("nombre", ""))
		d.erase("nombre")
		return d)
	var rep := ImportReport.new()
	var imp := PackageImporter.new(st.library)
	var files := {"character.json": JSON.stringify({"schema": "simhalla.character/1", "nombre": "Zed"}).to_utf8_buffer(),
		"ai.json": JSON.stringify({"schema": "simhalla.ai/1"}).to_utf8_buffer()}
	var parsed := imp._parse_json_files(files, rep)
	assert_eq(parsed["character.json"]["name"], "Zed")
	assert_eq(parsed["character.json"]["schema"], "simhalla.character/2")
	assert_eq(parsed["ai.json"]["schema"], "simhalla.ai/1")
	assert_eq(rep.warnings.size(), 1)
	assert_contains(rep.warnings[0], "[migrado]")
	assert_true(rep.errors.is_empty())
	shared.set_current("character", 1)
	rep = ImportReport.new()
	var fut := imp._parse_json_files({"character.json": JSON.stringify({"schema": "simhalla.character/2"}).to_utf8_buffer()}, rep)
	assert_false(fut.has("character.json"))
	assert_contains(rep.errors[0], "[schema_futuro]")
	# restaurar el estado compartido
	shared.current = old_cur
	shared.steps = old_steps
	ContentLibrary._remove_tree(TMP)
