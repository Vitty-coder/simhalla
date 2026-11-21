extends TestCase
## Fase 9 (interfaz): escena principal Godot automatizada en modo headless — navegacion, adaptabilidad, flujo completo
## importacion -> duelo -> visor -> informe y lotes, localizacion, retratos y textos de eventos.

const TMP := "user://_tests_phase9c"
const FX := "res://content/fixtures/entities/"
var _n := 0


func _tree() -> SceneTree:
	return TestCase.scene_tree


func _app() -> AppController:
	_n += 1
	var a := AppController.new("%s/u%d_%d" % [TMP, Time.get_ticks_usec(), _n])
	assert_eq(a.boot(), [])
	return a


func _main(a: AppController) -> MainUI:
	var m: MainUI = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	m.app = a
	m.build_ui() # el arbol aun no esta inicializado durante _init del ejecutor: se construye explicitamente
	return m


func _close(m: MainUI) -> void:
	m.free()


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


func _find(m: MainUI, name: String) -> Node:
	return m.find_child(name, true, false)


func _press(m: MainUI, name: String) -> void:
	var b := _find(m, name) as Button
	assert_true(b != null, "falta el boton %s" % name)
	if b != null:
		assert_false(b.disabled, "el boton %s esta desactivado" % name)
		b.pressed.emit()


func _texts(node: Node) -> String:
	var out := ""
	if node is Label:
		out += (node as Label).text + "\n"
	if node is Button:
		out += (node as Button).text + "\n"
	for c in node.get_children():
		out += _texts(c)
	return out


# --- estructura y adaptabilidad ---------------------------------------------------------------------------------------------

func test_main_scene_builds_all_screens_and_navigates() -> void:
	var a := _app()
	var m := _main(a)
	assert_eq(m.nav_buttons.size(), 10)
	assert_eq(m.screen_node.get_class(), "VBoxContainer")
	for s in AppController.SCREENS:
		assert_true(a.go(s), s)
		assert_true(m.screen_node != null, "pantalla %s" % s)
		assert_true(m.screen_node is BaseScreen)
		assert_eq((m.nav_buttons[s] as Button).disabled, true, "la pantalla actual se marca")
		assert_true(_texts(m.screen_node).length() > 0 or s == "viewer" or s == "debug")
	assert_true(a.back())
	assert_contains(m.status.text, "Modo libre", "el modo siempre visible")
	assert_contains(m.status.text, "PRUEBA", "perfil ilustrativo señalado")
	_close(m)
	ContentLibrary._remove_tree(TMP)


func test_adaptive_layout_wide_vs_narrow_and_touch_targets() -> void:
	var a := _app()
	var m := _main(a)
	m.apply_layout(1280.0)
	assert_eq(m.layout_kind, "wide")
	assert_false(m.root_box.vertical, "barra lateral")
	assert_true(m.nav.vertical)
	assert_eq(m.root_box.get_child(0), m.nav, "navegacion a la izquierda")
	assert_eq((m.nav_buttons["library"] as Button).text, "Biblioteca")
	m.apply_layout(420.0)
	assert_eq(m.layout_kind, "narrow")
	assert_true(m.root_box.vertical, "barra inferior en pantallas estrechas")
	assert_false(m.nav.vertical)
	assert_eq(m.root_box.get_child(m.root_box.get_child_count() - 1), m.nav, "navegacion abajo")
	assert_eq((m.nav_buttons["library"] as Button).text, "Biblio", "texto corto")
	assert_eq((m.nav_buttons["library"] as Button).tooltip_text, "Biblioteca")
	for s in m.nav_buttons:
		assert_true((m.nav_buttons[s] as Button).custom_minimum_size.y >= UIKit.TOUCH_MIN, "objetivo tactil >= 48 px")
	a.go("duel")
	for b in m.screen_node.find_children("*", "Button", true, false):
		assert_true((b as Button).custom_minimum_size.y >= 32.0, "ningun boton diminuto")
	assert_true(_find(m, "start_btn") == null or (_find(m, "start_btn") as Button).custom_minimum_size.y >= UIKit.TOUCH_MIN)
	m.apply_layout(1280.0)
	assert_eq(m.layout_kind, "wide")
	_close(m)
	ContentLibrary._remove_tree(TMP)


# --- flujo completo desde la interfaz -------------------------------------------------------------------------------------------

func test_full_flow_import_library_duel_viewer_save_report() -> void:
	var a := _app()
	var m := _main(a)
	var dir := _pkg_dir({"ATK": 150})
	# importacion
	a.go("import")
	var imp := m.screen_node as ImportScreen
	imp.path_edit.text = dir
	_press(m, "validate_btn")
	assert_true(_texts(m.screen_node).contains("t/hero@1.0.0"), "la vista previa muestra id@version")
	assert_true(_texts(m.screen_node).contains("Coste de creación"), "coste y presupuesto antes de importar")
	assert_eq(a.library.entries().size(), 0)
	_press(m, "import_btn")
	assert_eq(a.library.entries().size(), 1)
	assert_contains(_texts(m.screen_node), "Importado t/hero@1.0.0")
	# biblioteca y detalle
	a.go("library")
	_press(m, "entry_t_hero_1_0_0")
	var txt := _texts(m.screen_node)
	assert_contains(txt, "Integridad verificada")
	assert_contains(txt, "Coste de creación")
	assert_contains(txt, "ILUSTRATIVO")
	# duelo: añadir el paquete y un adversario desde la interfaz
	a.go("duel")
	var duel := m.screen_node as DuelScreen
	var srcs := DuelScreen.sources(a)
	var idx_pkg := srcs.find_custom(func(s): return s["ref"] == "t/hero")
	var idx_file := srcs.find_custom(func(s): return str(s["ref"]).ends_with("attacker_b.json"))
	assert_true(idx_pkg >= 0 and idx_file >= 0)
	assert_true((_find(m, "start_btn") as Button).disabled, "sin contendientes no se puede empezar")
	duel.source_option.select(idx_pkg)
	_press(m, "add_btn")
	(_find(m, "source_option") as OptionButton).select(idx_file)
	_press(m, "add_btn")
	assert_eq(a.duel.entities.size(), 2)
	var dtxt := _texts(m.screen_node)
	assert_contains(dtxt, "versión 1.0.0")
	assert_contains(dtxt, "Modo libre")
	assert_false((_find(m, "start_btn") as Button).disabled)
	_press(m, "start_btn")
	assert_eq(a.screen, "viewer")
	assert_true(a.viewer != null)
	# visor
	var vs := m.screen_node as ViewerScreen
	assert_eq(vs.cards.get_child_count(), 2, "dos tarjetas de entidad")
	assert_true(_find(m, "card_e1") != null)
	var step0: int = a.viewer.position()["step"]
	_press(m, "step_action_btn")
	assert_eq(a.viewer.position()["step"], step0 + 1)
	_press(m, "play_btn")
	assert_true(a.viewer.playing)
	for i in 3:
		vs._process(0.2)
	assert_true(a.viewer.position()["step"] > step0 + 1, "reproduce al avanzar el tiempo")
	_press(m, "play_btn")
	assert_false(a.viewer.playing)
	var at: int = a.viewer.position()["step"]
	_press(m, "rewind_btn")
	assert_eq(a.viewer.position()["step"], at - 1)
	vs.slider.value_changed.emit(2.0) # en ejecucion real lo emite el propio deslizador al moverlo
	assert_eq(a.viewer.position()["step"], 2, "el deslizador salta (retrocede reconstruyendo)")
	_press(m, "to_end_btn")
	assert_contains((_find(m, "seek_slider") as HSlider).get_parent().get_parent().find_children("*", "Label", true, false).map(func(l): return (l as Label).text).reduce(func(x, y): return x + y, ""), "Resultado")
	(_find(m, "save_title") as LineEdit).text = "Duelo desde la UI"
	_press(m, "save_btn")
	assert_contains((_find(m, "save_msg") as Label).text, "Guardado: combate b0001")
	assert_eq(a.storage.battles.list().size(), 1)
	# informes: el nuevo informe aparece y se abre de forma nativa y verificada
	a.go("reports")
	var rtxt := _texts(m.screen_node)
	assert_contains(rtxt, "r0001")
	_press(m, "open_r0001")
	assert_true(_find(m, "report_view") != null)
	assert_true((_find(m, "report_view") as ReportView).get_child_count() > 10)
	assert_contains(_texts(m.screen_node), "Informe verificado")
	_press(m, "replay_b0001")
	assert_eq(a.screen, "viewer", "reproducir el combate guardado abre el visor")
	assert_true(a.viewer.matches_saved)
	_close(m)
	ContentLibrary._remove_tree(TMP)


func test_batch_screen_runs_and_reports() -> void:
	var a := _app()
	var m := _main(a)
	a.go("batch")
	var bs := m.screen_node as BatchScreen
	var list := _find(m, "contestant_list") as ItemList
	var srcs := bs.sources_cache
	var ia := srcs.find_custom(func(s): return str(s["ref"]).ends_with("attacker_a.json"))
	var ib := srcs.find_custom(func(s): return str(s["ref"]).ends_with("attacker_b.json"))
	list.select(ia, false)
	list.multi_selected.emit(ia, true)
	list.select(ib, false)
	list.multi_selected.emit(ib, true)
	bs.reps = 5
	_press(m, "prepare_btn")
	assert_contains(_texts(m.screen_node), "Plan listo: 1 escenarios, 5 trabajos")
	_press(m, "run_btn")
	var guard := 0
	while a.batch.is_running() and guard < 300:
		(m.screen_node as BatchScreen)._process(0.1)
		guard += 1
	assert_false(a.batch.is_running())
	assert_eq(a.batch.result.executed, 5)
	assert_contains(_texts(m.screen_node), "Lote complete: 5 trabajos")
	_press(m, "batch_save_btn")
	assert_eq(a.storage.batches.list().size(), 1)
	_press(m, "batch_report_btn")
	assert_eq(a.screen, "reports")
	assert_true(_find(m, "report_view") != null, "el informe del lote se abre")
	assert_eq(a.reports.list().size(), 1)
	# pocos contendientes: error claro
	a.go("batch")
	(m.screen_node as BatchScreen).picks.clear()
	_press(m, "prepare_btn")
	assert_contains(_texts(m.screen_node), "al menos dos contendientes")
	_close(m)
	ContentLibrary._remove_tree(TMP)


func test_settings_change_language_and_regulated_blocks_start_from_the_ui() -> void:
	var a := _app()
	var m := _main(a)
	assert_true(a.importer.commit(_pkg_dir({"ATK": 5000}, "t/giant"))["ok"])
	a.go("settings")
	((_find(m, "locale_option")) as OptionButton).select(1)
	((_find(m, "mode_setting")) as OptionButton).select(1)
	_press(m, "save_settings_btn")
	assert_eq(a.settings()["locale"], "en")
	assert_eq(a.settings()["default_mode"], "regulated")
	assert_eq((m.nav_buttons["library"] as Button).text, "Library" if m.layout_kind == "wide" else "Lib", "la interfaz cambia de idioma")
	assert_contains(_texts(m.screen_node), "Settings saved")
	a.save_settings({"default_budget": "small"})
	a.duel.reset()
	a.duel.add_package("t/giant")
	a.duel.add_file(FX + "attacker_b.json")
	a.go("duel")
	assert_true((_find(m, "start_btn") as Button).disabled, "reglamentado fuera de presupuesto: no se puede empezar")
	var t := _texts(m.screen_node)
	assert_contains(t, "Regulated mode")
	assert_contains(t, "[presupuesto]")
	a.save_settings({"locale": "es", "default_mode": "free"})
	a.duel.reset()
	a.duel.add_package("t/giant")
	a.duel.add_file(FX + "attacker_b.json")
	a.go("library")
	a.go("duel")
	assert_false((_find(m, "start_btn") as Button).disabled, "libre: solo avisa")
	assert_contains(_texts(m.screen_node), "Modo libre")
	# reglas y depuracion
	a.go("rules")
	assert_contains(_texts(m.screen_node), "ILUSTRATIVO")
	_press(m, "evaluate_btn")
	assert_contains(_texts(m.screen_node), "Coste de creación")
	a.go("debug")
	assert_contains(_texts(m.screen_node), "No hay ningún combate abierto")
	_close(m)
	ContentLibrary._remove_tree(TMP)


func test_debug_screen_shows_internal_state_of_the_open_battle() -> void:
	var a := _app()
	var m := _main(a)
	a.duel.add_file(FX + "attacker_a.json")
	a.duel.add_file(FX + "attacker_b.json")
	assert_true(a.duel.start()["ok"])
	a.viewer.to_end()
	a.go("debug")
	var st := _find(m, "debug_state") as TextEdit
	assert_true(st != null)
	assert_contains(st.text, "\"stats\"")
	assert_contains(st.text, "ai_memory")
	assert_contains(st.text, "modifiers")
	_close(m)
	ContentLibrary._remove_tree(TMP)


# --- localizacion, retratos y textos ----------------------------------------------------------------------------------------------

func _source_keys() -> Dictionary:
	var keys := {}
	var rx := RegEx.create_from_string("(?:\\bt|LocaleService\\.t|UIKit\\.t)\\(\\s*\"([a-z0-9_.]+)\"")
	for dir in ["res://src/ui", "res://src/ui/screens", "res://src/application"]:
		var d := DirAccess.open(dir)
		for f in d.get_files():
			if f.ends_with(".gd"):
				for mt in rx.search_all(FileAccess.get_file_as_string(dir.path_join(f))):
					keys[mt.get_string(1)] = f
	return keys


func test_localization_covers_every_key_in_both_languages() -> void:
	LocaleService.load_all()
	var es := LocaleService.keys("es")
	var en := LocaleService.keys("en")
	assert_eq(es.size(), en.size())
	for k in es:
		assert_true(en.has(k), "en: falta %s" % k)
	var dynamic: Array = []
	for s in AppController.SCREENS:
		dynamic.append("nav." + s)
		dynamic.append("nav.%s.short" % s)
	for m in ["free", "regulated"]:
		dynamic.append("mode." + m)
	for m in BatchModel.MODES:
		dynamic.append("batch.mode_" + m)
		dynamic.append("batch.hint_" + m)
	for t in EventText.VISIBLE:
		dynamic.append("ev." + t)
	for k in dynamic:
		assert_true(es.has(k), "es: falta la clave dinamica %s" % k)
	var used := _source_keys()
	for k in used:
		if k.ends_with("_") or k.ends_with(".") or k == "nav." or k == "mode.":
			continue
		assert_true(es.has(k), "es: falta '%s' (usada en %s)" % [k, used[k]])
	# marcadores {n} coherentes entre idiomas
	var rx := RegEx.create_from_string("\\{(\\d)\\}")
	for k in es:
		LocaleService.set_locale("es")
		var raw_es := ""
		LocaleService.set_locale("es")
		var args := ["§0", "§1", "§2", "§3", "§4", "§5"]
		var s_es := LocaleService.t(k, args)
		LocaleService.set_locale("en")
		var s_en := LocaleService.t(k, args)
		for i in 6:
			assert_eq(s_es.contains("§%d" % i), s_en.contains("§%d" % i), "marcador {%d} distinto en '%s'" % [i, k])
		assert_eq(raw_es, "")
	LocaleService.set_locale("es")
	assert_eq(LocaleService.t("nav.library"), "Biblioteca")
	LocaleService.set_locale("en")
	assert_eq(LocaleService.t("nav.library"), "Library")
	assert_eq(str(TranslationServer.translate("nav.library")), "Library", "tr() de Godot tambien")
	assert_eq(LocaleService.t("clave.inexistente"), "clave.inexistente", "clave ausente: la propia clave")
	assert_true(LocaleService.missing.has("clave.inexistente"))
	assert_false(LocaleService.set_locale("xx"))
	assert_eq(LocaleService.t("library.cost", ["1", "2", "3"]), "Creation cost 1 CP · budget 2 CP · remaining 3")
	LocaleService.set_locale("es")


func test_event_texts_are_localized_and_noisy_events_hidden() -> void:
	LocaleService.set_locale("es")
	var ev := {"type": "damage_dealt", "source": "a", "target": "b", "data": {"applied": 40.0, "damage_type": "physical", "element": "fire", "crit": true}}
	assert_eq(EventText.describe(ev), "a causa 40 de daño (physical/fire) ★ a b")
	LocaleService.set_locale("en")
	assert_eq(EventText.describe(ev), "a deals 40 damage (physical/fire) ★ to b")
	LocaleService.set_locale("es")
	assert_eq(EventText.describe({"type": "action_selected", "source": "a", "target": "b", "data": {"kind": "wait"}}), "a espera")
	assert_contains(EventText.describe({"type": "combat_ended", "source": "", "target": "", "data": {"outcome": "win", "winner_team": "A", "reason": "last_team_standing"}}), "Fin del combate")
	assert_contains(EventText.describe({"type": "user.combo", "source": "a", "target": "", "data": {}}), "combo")
	assert_false(EventText.is_visible("time_advanced"))
	assert_false(EventText.is_visible("damage_pre"))
	assert_true(EventText.is_visible("death"))
	assert_true(EventText.is_visible("user.x"))
	assert_contains(EventText.describe({"type": "raro", "source": "a", "target": "b", "data": {}}), "raro")


func test_portraits_use_package_images_or_a_deterministic_placeholder() -> void:
	var p1 := PortraitProvider.placeholder("t/hero")
	var p2 := PortraitProvider.placeholder("t/hero")
	var p3 := PortraitProvider.placeholder("t/mage")
	assert_eq(p1.get_data(), p2.get_data(), "determinista")
	assert_ne(p1.get_data(), p3.get_data(), "distinto por id")
	assert_eq(p1.get_width(), PortraitProvider.SIZE)
	assert_eq(PortraitProvider.color_of("x"), PortraitProvider.color_of("x"))
	assert_eq(PortraitProvider.initials("Duelista arcano"), "DA")
	assert_eq(PortraitProvider.initials("examples/iron_vanguard"), "EI")
	assert_eq(PortraitProvider.initials(""), "?")
	var red := Image.create(16, 16, false, Image.FORMAT_RGBA8)
	red.fill(Color.RED)
	var png := red.save_png_to_buffer()
	var ld := PortraitProvider.load_image("x", {"assets/portrait.png": png})
	assert_true(ld["from_package"])
	assert_eq((ld["image"] as Image).get_pixel(3, 3), Color.RED)
	assert_false(PortraitProvider.load_image("x", {"assets/portrait.png": png.slice(0, 20)})["from_package"], "imagen corrupta: sustituto")
	assert_false(PortraitProvider.load_image("x", {})["from_package"])
	assert_true(PortraitProvider.texture("x") is ImageTexture)
	# un paquete con retrato lo expone en el detalle de la biblioteca
	var a := _app()
	var d := _pkg_dir({"ATK": 150}, "t/hero", "1.0.0", {"assets/portrait.png": png})
	var r := a.importer.commit(d)
	assert_true(r["ok"], str(r["errors"]))
	assert_true(a.library.detail("t/hero", "1.0.0")["portrait"])
	ContentLibrary._remove_tree(TMP)
