class_name BatchScreen
extends BaseScreen
## Configuracion y ejecucion masiva: modalidad, contendientes, repeticiones, semilla maestra, hilos y modo de semillas. Prepara el plan
## (fijando versiones), ejecuta con progreso y cancelacion, muestra el marcador incremental y permite guardar y generar el informe.

var mode: String = "duel"
var reps: int = 20
var master_seed: int = 1
var paired: bool = true
var axis_path: String = "stats.ATK"
var axis_values: String = "80,100,150"
var picks: Dictionary = {} ## indice de fuente -> seleccionado
var sources_cache: Array = []
var plan_msg: String = ""
var progress_bar: ProgressBar
var progress_label: Label
var live_box: VBoxContainer
var _prepared_ok: bool = false


func build() -> void:
	var bm := app.batch
	sources_cache = DuelScreen.sources(app)
	body.add_child(UIKit.header(t("nav.batch"), 1))
	body.add_child(context_line())
	var mode_opt := UIKit.option(BatchModel.MODES.map(func(m): return t("batch.mode_" + m)), null)
	mode_opt.select(BatchModel.MODES.find(mode))
	mode_opt.name = "batch_mode_option"
	mode_opt.item_selected.connect(func(i: int): mode = BatchModel.MODES[i]; _prepared_ok = false; refresh())
	body.add_child(UIKit.row([UIKit.label(t("batch.mode")), mode_opt]))
	body.add_child(UIKit.note(t("batch.hint_" + mode)))
	var list := ItemList.new()
	list.name = "contestant_list"
	list.select_mode = ItemList.SELECT_MULTI
	list.custom_minimum_size = Vector2(200, minf(40.0 * sources_cache.size() + 8.0, 220.0))
	for i in sources_cache.size():
		list.add_item(str(sources_cache[i]["text"]))
		if picks.get(i, false):
			list.select(i, false)
	list.multi_selected.connect(func(i: int, sel: bool): picks[i] = sel)
	body.add_child(list)
	var reps_box := SpinBox.new()
	reps_box.min_value = 1
	reps_box.max_value = 100000
	reps_box.value = reps
	reps_box.custom_minimum_size.y = UIKit.TOUCH_MIN
	reps_box.value_changed.connect(func(v: float): reps = int(v))
	var seed_box := SpinBox.new()
	seed_box.min_value = 0
	seed_box.max_value = 2147483647
	seed_box.value = master_seed
	seed_box.custom_minimum_size.y = UIKit.TOUCH_MIN
	seed_box.value_changed.connect(func(v: float): master_seed = int(v))
	var paired_cb := CheckBox.new()
	paired_cb.text = t("batch.paired")
	paired_cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	paired_cb.custom_minimum_size.y = UIKit.TOUCH_MIN
	paired_cb.button_pressed = paired
	paired_cb.toggled.connect(func(b: bool): paired = b)
	body.add_child(UIKit.row([UIKit.label(t("batch.reps")), reps_box, UIKit.label(t("batch.seed")), seed_box]))
	body.add_child(paired_cb)
	if mode == "sweep":
		var ap := UIKit.line_edit(axis_path)
		ap.text_changed.connect(func(s: String): axis_path = s)
		var av := UIKit.line_edit(axis_values)
		av.text_changed.connect(func(s: String): axis_values = s)
		body.add_child(UIKit.row([UIKit.label(t("batch.axis")), ap, av]))
	var prep := UIKit.button(t("batch.prepare"), func(): _prepare(); refresh())
	prep.name = "prepare_btn"
	body.add_child(prep)
	if plan_msg != "":
		body.add_child(UIKit.label(plan_msg) if _prepared_ok else UIKit.error(plan_msg))
	if _prepared_ok:
		var run := UIKit.button(t("batch.run"), func(): _run())
		run.name = "run_btn"
		var cancel := UIKit.button(t("batch.cancel"), func(): bm.cancel(); _update())
		cancel.name = "cancel_btn"
		body.add_child(UIKit.row([run, cancel]))
		progress_bar = ProgressBar.new()
		progress_bar.custom_minimum_size.y = 24
		body.add_child(progress_bar)
		progress_label = UIKit.label("")
		body.add_child(progress_label)
		live_box = UIKit.column()
		body.add_child(live_box)
		_update()


func _selected() -> Array:
	var out: Array = []
	for i in sources_cache.size():
		if picks.get(i, false):
			var s: Dictionary = sources_cache[i]
			var spec: Dictionary = {"package": s["ref"]} if s["kind"] == "pkg" else {"path": s["ref"]}
			out.append({"label": str(s["ref"]).get_file().get_basename(), "spec": spec})
	return out


func _prepare() -> void:
	var sel := _selected()
	var min_needed := 2 if mode != "tournament" else 3
	if sel.size() < 2:
		plan_msg = t("batch.err_pick_two")
		_prepared_ok = false
		return
	var spec := {"mode": mode, "reps": reps, "master_seed": master_seed, "paired": paired}
	match mode:
		"duel":
			spec["a"] = sel[0]["spec"]
			spec["b"] = sel[1]["spec"]
			spec["label_a"] = sel[0]["label"]
			spec["label_b"] = sel[1]["label"]
		"tournament":
			spec["contestants"] = sel
		"gauntlet":
			spec["subject"] = sel[0]
			spec["opponents"] = sel.slice(1)
		"compare_variants":
			var pk := str(sel[0]["spec"].get("package", ""))
			var vs: Array = app.library.versions_of(pk) if pk != "" else []
			var variants: Array = []
			for v in vs:
				variants.append({"label": "%s@%s" % [sel[0]["label"], v], "spec": {"package": pk, "version": v}})
			if variants.size() < 2:
				plan_msg = t("batch.err_two_versions")
				_prepared_ok = false
				return
			spec["variants"] = variants
			spec["opponent"] = sel[1]
		"compare_ai":
			spec["subject"] = sel[0]
			spec["opponent"] = sel[1]
			spec["ais"] = [{"label": "passive", "ai": DuelScreen.AI_PRESETS["passive"]}, {"label": "scored", "ai": DuelScreen.AI_PRESETS["scored"]}, {"label": "basic", "ai": DuelScreen.AI_PRESETS["priority_basic"]}]
		"compare_rulesets":
			spec["a"] = sel[0]
			spec["b"] = sel[1]
			spec["rulesets"] = [{"label": "base", "overrides": {}}, {"label": "turnos_20", "overrides": {"victory": {"limits": {"max_turns": 20}}}}]
		"sweep":
			spec["a"] = sel[0]
			spec["b"] = sel[1]
			var vals: Array = []
			for s in axis_values.split(",", false):
				if str(s).strip_edges().is_valid_float():
					vals.append(float(str(s).strip_edges()))
			spec["axes"] = [{"path": axis_path, "values": vals}]
	if min_needed > sel.size() and mode == "tournament":
		plan_msg = t("batch.err_pick_three")
		_prepared_ok = false
		return
	var r := app.batch.prepare(spec)
	_prepared_ok = bool(r["ok"])
	plan_msg = t("batch.plan_ready", [r.get("scenarios", 0), r.get("jobs", 0), app.batch.refs.size()]) if _prepared_ok else "; ".join(r["errors"])


func _run() -> void:
	app.batch.start()
	_update()


func _update() -> void:
	if progress_bar == null:
		return
	var bm := app.batch
	var p := bm.progress()
	if p.is_empty():
		return
	progress_bar.max_value = maxi(int(p["total"]), 1)
	progress_bar.value = int(p["done"])
	progress_label.text = t("batch.progress", [p["done"], p["total"], p["errors"]])
	UIKit.clear(live_box)
	var sm := bm.live_summary()
	if not sm.is_empty():
		var rows: Array = []
		for l in sm["by_label"]:
			var s: Dictionary = sm["by_label"][l]
			rows.append([l, s["games"], s["wins"], s["losses"], s["draws"]])
		live_box.add_child(UIKit.table([t("col.contender"), t("col.games"), t("col.wins"), t("col.losses"), t("col.draws")], rows, [1, 2, 3, 4]))
	if bm.result != null:
		live_box.add_child(UIKit.label(t("batch.done", [bm.result.status, bm.result.executed, bm.result.fingerprint.substr(0, 12)])))
		var msg := UIKit.label("")
		msg.name = "batch_msg"
		var sv := UIKit.button(t("batch.save"), func():
			var r := bm.save(bm.plan.name)
			msg.text = t("batch.saved", [str(r.get("id", ""))]) if bool(r["ok"]) else str(r["error"]))
		sv.name = "batch_save_btn"
		var rp := UIKit.button(t("batch.report"), func():
			var r := bm.save_report()
			msg.text = t("batch.report_saved", [str(r.get("id", ""))]) if bool(r["ok"]) else str(r["error"])
			if bool(r["ok"]):
				app.go("reports", {"open": str(r["id"])}))
		rp.name = "batch_report_btn"
		live_box.add_child(UIKit.row([sv, rp]))
		live_box.add_child(msg)


func _process(_delta: float) -> void:
	var bm := app.batch
	if bm == null or not bm.is_running():
		return
	if int(app.settings()["workers"]) <= 0:
		bm.step(2, 6)
	else:
		bm.poll()
	_update()
