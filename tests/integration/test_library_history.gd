extends TestCase
## Historial persistente de la biblioteca y exportacion de la biblioteca como bundle de paquetes.

const TMP := "user://_tests_libhist"
var _n := 0


func _app() -> AppController:
	_n += 1
	var a := AppController.new("%s/h%d_%d" % [TMP, Time.get_ticks_usec(), _n])
	assert_eq(a.boot(), [])
	return a


func test_history_records_operations_in_order_and_persists() -> void:
	var a := _app()
	assert_eq(a.storage.history(), [])
	var r := a.install_examples()
	assert_eq(r["errors"], [])
	var h := a.storage.history()
	assert_eq(h.size(), 6)
	assert_eq(h[0]["seq"], 1)
	assert_eq(h[5]["seq"], 6)
	assert_eq(h[0]["action"], "install_example")
	a.install_examples() # idempotente: no registra de nuevo
	assert_eq(a.storage.history().size(), 6)
	assert_eq(a.storage.remove_package("examples/arcane_duelist", "1.0.0"), "")
	var last: Dictionary = a.storage.history()[-1]
	assert_eq(last["action"], "remove_package")
	assert_eq(last["target"], "examples/arcane_duelist@1.0.0")
	assert_eq(a.library.history(2).size(), 2)
	# persistente: otra instancia sobre el mismo directorio lo ve
	var b := AppStorage.new(a.storage.root)
	assert_eq(b.history().size(), 7)
	assert_eq(b.log_event("x", "y"), 8)
	# un borrado rechazado no se registra
	assert_true(a.storage.remove_package("no/existe", "1.0.0") != "")
	assert_eq(a.storage.history().size(), 8)
	ContentLibrary._remove_tree(TMP)


func test_history_is_capped_and_tolerates_corruption() -> void:
	var s := AppStorage.new("%s/cap%d" % [TMP, Time.get_ticks_usec()])
	for i in AppStorage.HISTORY_MAX + 5:
		s.log_event("t", str(i))
	var h := s.history()
	assert_eq(h.size(), AppStorage.HISTORY_MAX)
	assert_eq(h[-1]["seq"], AppStorage.HISTORY_MAX + 5)
	var f := FileAccess.open(s.history_path(), FileAccess.WRITE)
	f.store_string("{no json")
	f.close()
	assert_eq(s.history(), [], "historial ilegible: se ignora")
	assert_eq(s.log_event("t", "x"), 1, "y se reinicia sin bloquear la operacion")
	ContentLibrary._remove_tree(TMP)


func test_import_commit_logs_and_new_version_is_distinguished() -> void:
	var a := _app()
	var r: Dictionary = a.importer.commit("res://content/packages/core_spells")
	assert_true(r["ok"], str(r))
	var h := a.storage.history()
	assert_eq(h.size(), 1)
	assert_eq(h[0]["action"], "import")
	a.importer.commit("res://content/packages/core_spells") # ya presente: sin registro
	assert_eq(a.storage.history().size(), 1)
	ContentLibrary._remove_tree(TMP)


func test_export_library_roundtrip_to_another_installation() -> void:
	var a := _app()
	a.install_examples()
	var path := a.storage.root.path_join("exports/lib.simbundle")
	var ex := a.library.export_library(path)
	assert_true(ex["ok"], str(ex))
	assert_eq(ex["packages"], 6)
	assert_eq(ex["records"], 0)
	assert_eq(a.storage.history()[a.storage.history().size() - 1]["action"], "export")
	var b := _app()
	var im := BundleIO.import_bundle(b.storage, path)
	assert_true(im["ok"], str(im))
	assert_eq(im["packages"].size(), 6)
	assert_eq(b.storage.history()[-1]["action"], "bundle_import")
	for e in a.library.entries():
		assert_eq(b.storage.library.entry(e["id"], e["version"])["hash"], a.storage.library.entry(e["id"], e["version"])["hash"], "misma huella tras el viaje")
	# seleccion parcial, inexistente y vacia
	var one := a.library.export_library(a.storage.root.path_join("exports/one.simbundle"), ["examples/basic_ai@1.0.0"])
	assert_true(one["ok"])
	assert_eq(one["packages"], 1)
	assert_false(a.library.export_library(a.storage.root.path_join("exports/x.simbundle"), ["no/existe@1.0.0"])["ok"])
	assert_false(_app().library.export_library(a.storage.root.path_join("exports/y.simbundle"))["ok"], "biblioteca vacia")
	# un paquete alterado en disco no se exporta
	var lp := a.storage.library.load_package("examples/basic_ai", "1.0.0")
	var fpath := a.storage.library.entry_dir("examples/basic_ai", "1.0.0").path_join(str((lp["files"] as Dictionary).keys()[0]))
	var f := FileAccess.open(fpath, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	assert_false(a.library.export_library(a.storage.root.path_join("exports/z.simbundle"), ["examples/basic_ai@1.0.0"])["ok"])
	ContentLibrary._remove_tree(TMP)


func test_library_screen_shows_history_and_exports() -> void:
	var a := _app()
	a.install_examples()
	var m: MainUI = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	m.app = a
	m.build_ui()
	a.go("library")
	assert_true(m.find_child("history_box", true, false) != null)
	assert_eq((m.find_child("history_box", true, false) as VBoxContainer).get_child_count(), 6)
	var b := m.find_child("export_library_btn", true, false) as Button
	assert_true(b != null)
	b.pressed.emit()
	assert_true(FileAccess.file_exists(a.storage.root.path_join("exports/library.simbundle")))
	m.free()
	ContentLibrary._remove_tree(TMP)


func test_bundles_include_transitive_dependencies_and_import_in_a_clean_installation() -> void:
	var a := _app()
	a.install_examples()
	# un combate guardado con un personaje que depende de otros paquetes
	a.duel.reset()
	a.duel.add_package("examples/arcane_duelist")
	a.duel.add_package("examples/iron_vanguard")
	var vm: ViewerModel = a.duel.start()["viewer"]
	vm.to_end()
	var bid: String = vm.save("con dependencias", false)["id"]
	var path := a.storage.root.path_join("exports/dep.simbundle")
	var ex := BundleIO.export_records(a.storage, [{"store": "battles", "id": bid}], path)
	assert_true(ex["ok"], str(ex))
	assert_eq(ex["packages"], 4, "arcane_duelist + iron_vanguard + core_spells + basic_ai")
	var b := _app()
	var im := BundleIO.import_bundle(b.storage, path)
	assert_true(im["ok"], str(im))
	assert_true(b.storage.library.has("examples/core_spells", "1.2.0"))
	assert_true(b.storage.library.has("examples/basic_ai", "1.0.0"))
	assert_true(b.storage.replay_battle(im["records"][0]["new_id"])["matches"], "el combate importado se reproduce igual en una instalacion limpia")
	# exportar solo un paquete con dependencias arrastra sus dependencias
	var one := a.library.export_library(a.storage.root.path_join("exports/one_dep.simbundle"), ["examples/arcane_duelist@1.0.0"])
	assert_true(one["ok"], str(one))
	assert_eq(one["packages"], 3)
	# dependencia ausente: error explicito
	assert_eq(a.storage.remove_package("examples/basic_ai", "1.0.0", true), "")
	var miss := a.library.export_library(a.storage.root.path_join("exports/miss.simbundle"), ["examples/arcane_duelist@1.0.0"])
	assert_false(miss["ok"])
	assert_contains(miss["errors"][0], "[dependencia]")
	ContentLibrary._remove_tree(TMP)
