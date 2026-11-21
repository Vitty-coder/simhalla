class_name RulesScreen
extends BaseScreen
## Reglamentos y equilibrio: elementos versionados (con validacion y aviso de perfil ILUSTRATIVO), perfil activo, importacion de
## archivos con colision explicita y valoracion de un personaje con el perfil/modo/presupuesto elegidos.

var eval_pkg: String = ""
var eval_result: Dictionary = {}
var import_msg: String = ""
var calib_picks: Dictionary = {} ## indice -> bool
var calib_reps: int = 10
var calib_msg: String = ""
var calib_bar: ProgressBar
var calib_label: Label
var calib_box: VBoxContainer
var calib_running: bool = false


func build() -> void:
	body.add_child(UIKit.header(t("nav.rules"), 1))
	body.add_child(UIKit.header(t("rules.rulesets"), 2))
	for r in app.rules.rulesets():
		var d := app.rules.ruleset_detail(str(r["id"]), str(r["version"]))
		body.add_child(UIKit.label("%s@%s · %s · %s" % [r["id"], r["version"], str(r["hash"]).substr(0, 12), t("rules.valid") if bool(d.get("ok", false)) else t("rules.invalid")]))
	body.add_child(UIKit.header(t("rules.profiles"), 2))
	var ids: Array = []
	for p in app.rules.profiles():
		var d := app.rules.profile_detail(str(p["id"]), str(p["version"]))
		ids.append(p["id"])
		body.add_child(UIKit.label("%s@%s · %s · %s" % [p["id"], p["version"], t("rules.has_costs") if bool(d.get("has_costs", false)) else t("rules.no_costs"), t("rules.illustrative") if bool(d.get("illustrative", false)) else ""]))
		if str(d.get("notice", "")) != "":
			body.add_child(UIKit.warn(str(d["notice"])))
		if not (d.get("budgets", {}) as Dictionary).is_empty():
			body.add_child(UIKit.note(t("rules.budgets", [", ".join(d["budgets"].keys().map(func(k): return "%s=%s" % [k, ReportDocument.num(d["budgets"][k]["points"])]))])))
	var active := UIKit.option(ids, str(app.settings()["default_profile"]))
	active.name = "active_profile"
	active.item_selected.connect(func(i: int): app.rules.set_active_profile(ids[i]); refresh())
	body.add_child(UIKit.row([UIKit.label(t("rules.active_profile")), active]))
	body.add_child(context_line())
	# importar archivo
	body.add_child(UIKit.header(t("rules.import"), 2))
	var path := UIKit.line_edit("", t("import.path_placeholder"))
	var rid := UIKit.line_edit("user/mi_reglamento", "namespace/nombre")
	var ver := UIKit.line_edit("1.0.0", "1.0.0")
	var kind := UIKit.option(["ruleset", "profile"], "ruleset")
	var go := UIKit.button(t("rules.import_btn"), func():
		var r := app.rules.import_file(["ruleset", "profile"][kind.selected], path.text, rid.text, ver.text, "reject")
		import_msg = t("rules.imported", [rid.text, str(r.get("version", ""))]) if bool(r["ok"]) else str(r["error"])
		refresh())
	body.add_child(UIKit.row([kind, path]))
	body.add_child(UIKit.row([rid, ver, go]))
	if import_msg != "":
		body.add_child(UIKit.label(import_msg))
	# valorar un personaje
	body.add_child(UIKit.header(t("rules.evaluate"), 2))
	var pkgs: Array = []
	for e in app.library.entries({"type": "character"}):
		pkgs.append("%s@%s" % [e["id"], e["version"]])
	if pkgs.is_empty():
		body.add_child(UIKit.note(t("library.empty")))
	else:
		var po := UIKit.option(pkgs, eval_pkg if eval_pkg != "" else pkgs[0])
		var ev := UIKit.button(t("rules.evaluate_btn"), func():
			eval_pkg = pkgs[po.selected]
			var parts: PackedStringArray = eval_pkg.split("@")
			eval_result = app.rules.evaluate(parts[0], parts[1], "", app.mode(), app.budget())
			refresh())
		ev.name = "evaluate_btn"
		body.add_child(UIKit.row([po, ev]))
		if not eval_result.is_empty():
			for e in eval_result.get("technical_errors", []):
				body.add_child(UIKit.error(str(e)))
			if eval_result.has("items"):
				body.add_child(UIKit.label(t("library.cost", [ReportDocument.num(eval_result["creation_cost"]), ReportDocument.num(eval_result["budget"]["points"]), ReportDocument.num(eval_result["remaining"])])))
				body.add_child(UIKit.table([t("col.component"), t("col.type"), t("col.rule"), t("col.amount")], eval_result["items"].filter(func(i): return bool(i["counted"])).map(func(i): return [i["id"], i["kind"], i["rule"], ReportDocument.num(i["amount"])]), [3]))
				for u in eval_result["unevaluable"]:
					body.add_child(UIKit.warn("%s: %s" % [u["id"], u["reason"]]))
	if not pkgs.is_empty():
		_build_calibration(pkgs)


# --- Calibracion empirica de costes (D-118) -----------------------------------------------------------------------------------

func _build_calibration(pkgs: Array) -> void:
	body.add_child(UIKit.header(t("rules.calibrate"), 2))
	body.add_child(UIKit.note(t("rules.calibrate_hint")))
	for i in pkgs.size():
		var cb := CheckBox.new()
		cb.text = str(pkgs[i])
		cb.name = "calib_pick_%d" % i
		cb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		cb.custom_minimum_size.y = UIKit.TOUCH_MIN
		cb.button_pressed = bool(calib_picks.get(i, false))
		cb.toggled.connect(func(on: bool): calib_picks[i] = on)
		body.add_child(cb)
	var reps := SpinBox.new()
	reps.min_value = 2
	reps.max_value = 200
	reps.value = calib_reps
	reps.custom_minimum_size.y = UIKit.TOUCH_MIN
	reps.name = "calib_reps"
	reps.value_changed.connect(func(v: float): calib_reps = int(v))
	var run := UIKit.button(t("rules.calib_run"), func(): _calib_start(pkgs, calib_reps))
	run.name = "calib_run_btn"
	var cancel := UIKit.button(t("rules.calib_cancel"), func(): app.rules.cancel_calibration(); calib_running = false; _calib_show())
	cancel.name = "calib_cancel_btn"
	body.add_child(UIKit.row([UIKit.label(t("batch.reps")), reps, run, cancel]))
	calib_bar = ProgressBar.new()
	calib_bar.custom_minimum_size.y = 22
	body.add_child(calib_bar)
	calib_label = UIKit.label("")
	body.add_child(calib_label)
	calib_box = UIKit.column()
	body.add_child(calib_box)
	_calib_show()


func _calib_start(pkgs: Array, reps: int) -> void:
	var ids: Array = []
	for i in pkgs.size():
		if bool(calib_picks.get(i, false)):
			ids.append(str(pkgs[i]))
	var r := app.rules.begin_calibration(ids, {"reps": reps, "master_seed": 1})
	calib_running = bool(r["ok"])
	if calib_running:
		calib_bar.max_value = maxf(float(app.rules.calibration_progress().get("total", 1)), 1.0)
		calib_bar.value = 0
	_calib_show()


## Un tramo corto por fotograma: la interfaz sigue respondiendo mientras se juega el torneo.
func _process(_delta: float) -> void:
	if not calib_running:
		return
	var more := app.rules.calibration_step(8)
	var p := app.rules.calibration_progress()
	if calib_bar != null and not p.is_empty():
		calib_bar.value = float(p["done"])
		calib_label.text = t("rules.calib_running", [p["done"], p["total"]])
	if not more:
		calib_running = false
		_calib_show()


func _calib_show() -> void:
	if calib_box == null:
		return
	UIKit.clear(calib_box)
	var r: Dictionary = app.rules.calib_result
	if calib_msg != "":
		calib_box.add_child(UIKit.label(calib_msg))
	if r.is_empty():
		return
	if not bool(r.get("ok", false)):
		calib_box.add_child(UIKit.error("; ".join(r.get("errors", []))))
		return
	calib_box.add_child(UIKit.warn(t("balance.illustrative")))
	for w in r["warnings"]:
		calib_box.add_child(UIKit.warn(str(w)))
	var sm: Dictionary = r["summary"]
	calib_box.add_child(UIKit.label(t("rules.calib_spearman", ["%.3f" % sm["spearman_before"], ("%.3f" % sm["spearman_after"]) if sm.has("spearman_after") else "—"])))
	calib_box.add_child(UIKit.table([t("col.component"), t("col.cost"), t("col.score"), t("col.rating"), t("col.verdict")],
		r["entities"].map(func(e): return [e["label"], ReportDocument.num(e["cost"]), "%.3f" % e["score"], "%.2f" % e["rating"], e["verdict"]]), [1, 2, 3]))
	calib_box.add_child(UIKit.table([t("col.type"), "beta", t("col.multiplier"), t("col.identifiable")],
		r["categories"].map(func(c): return [c["id"], "%.4f" % c["beta"], "%.3f" % c["multiplier"], t("col.yes") if bool(c["identifiable"]) else t("col.no")]), [1, 2]))
	if r["suggested_profile"] != null:
		var save := UIKit.button(t("rules.calib_save"), func():
			var sv := app.rules.save_calibrated(r)
			calib_msg = t("rules.calib_saved", [str(sv.get("id", "")), str(sv.get("version", ""))]) if bool(sv["ok"]) else str(sv["error"])
			refresh())
		save.name = "calib_save_btn"
		calib_box.add_child(save)
