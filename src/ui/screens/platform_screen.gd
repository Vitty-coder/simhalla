class_name PlatformScreen
extends BaseScreen
## Diagnostico de plataforma: comprueba en ESTE dispositivo que el motor da los mismos resultados que la referencia (determinismo
## multiplataforma) y mide el rendimiento real. Es la via para verificar Android sin herramientas externas. El informe se guarda en el
## directorio de datos de la aplicacion y se muestra completo (incluidas las incompatibilidades).

var pc: PlatformCheck = null
var running: bool = false
var progress_label: Label
var progress_bar: ProgressBar
var result_box: VBoxContainer
var saved_path: String = ""


func build() -> void:
	body.add_child(UIKit.header(t("nav.platform"), 1))
	body.add_child(UIKit.note(t("platform.hint")))
	var go := UIKit.button(t("platform.run"), func(): _start())
	go.name = "platform_run_btn"
	body.add_child(go)
	progress_bar = ProgressBar.new()
	progress_bar.custom_minimum_size.y = 22
	body.add_child(progress_bar)
	progress_label = UIKit.label("")
	body.add_child(progress_label)
	result_box = UIKit.column()
	body.add_child(result_box)
	if pc != null:
		_show_result()


func _start() -> void:
	pc = PlatformCheck.new({"bench_ms": 700})
	running = true
	progress_bar.max_value = pc.total()
	progress_bar.value = 0
	UIKit.clear(result_box)


## Una tarea por fotograma: la interfaz no se bloquea.
func _process(_delta: float) -> void:
	if not running or pc == null:
		return
	progress_label.text = t("platform.running", [pc.current_name(), pc.done() + 1, pc.total()])
	if not pc.step():
		running = false
		_show_result()
	progress_bar.value = pc.done()


func _show_result() -> void:
	UIKit.clear(result_box)
	var rep := pc.report()
	var ok := bool(rep["summary"]["compatible"])
	progress_bar.value = progress_bar.max_value
	progress_label.text = ""
	result_box.add_child(UIKit.header(t("platform.compatible") if ok else t("platform.incompatible"), 2))
	result_box.add_child(UIKit.label(t("platform.summary", [rep["summary"]["passed"], rep["summary"]["failed"]])))
	result_box.add_child(UIKit.table([t("col.field"), t("col.value")], pc.info.keys().map(func(k): return [k, str(pc.info[k])])))
	var rows: Array = []
	for c in pc.checks:
		rows.append([c["name"], "info" if c["kind"] == "info" else ("OK" if bool(c["ok"]) else "FALLO"), c["detail"]])
	result_box.add_child(UIKit.table([t("col.type"), t("col.result"), t("col.detail")], rows))
	for c in pc.checks:
		if c["kind"] == "check" and not bool(c["ok"]):
			result_box.add_child(UIKit.error("%s: %s" % [c["name"], c["detail"]]))
	if not pc.perf.is_empty():
		result_box.add_child(UIKit.table([t("col.scenario"), t("col.duels"), "ms", t("col.duels_per_s"), t("col.events_per_s"), t("col.target"), t("col.meets")],
			pc.perf.map(func(p): return [p["scenario"], p["duels"], p["ms"], "%.1f" % p["duels_per_s"], "%.0f" % p["events_per_s"], "%.1f" % p["target"], t("col.yes") if bool(p["meets"]) else t("col.no")]), [1, 2, 3, 4, 5]))
	var sv := UIKit.button(t("platform.save"), func():
		saved_path = PlatformScreen.save_report(app, pc)
		_show_result())
	sv.name = "platform_save_btn"
	result_box.add_child(sv)
	if saved_path != "":
		result_box.add_child(UIKit.label(t("platform.saved", [ProjectSettings.globalize_path(saved_path)])))


## Guarda el informe (JSON + Markdown) en <datos>/platform/. Devuelve la ruta del JSON.
static func save_report(a: AppController, check: PlatformCheck) -> String:
	var dir := a.storage.root.path_join("platform")
	DirAccess.make_dir_recursive_absolute(dir)
	var base := "platform_%s_%s" % [str(check.info.get("os", "x")).to_lower(), str(check.info.get("arch", "x")).to_lower()]
	var f := FileAccess.open(dir.path_join(base + ".json"), FileAccess.WRITE)
	f.store_string(JSON.stringify(check.report(), "  ", true, true))
	f.close()
	var m := FileAccess.open(dir.path_join(base + ".md"), FileAccess.WRITE)
	m.store_string(check.to_markdown())
	m.close()
	return dir.path_join(base + ".json")
