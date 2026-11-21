class_name ReportsScreen
extends BaseScreen
## Informes, combates y lotes guardados: abrir (vista nativa), verificar, exportar archivos, borrar (protegido), reproducir un combate
## y generar informes desde combates/lotes.

var opened: String = ""
var message: String = ""
var query: String = ""


func build() -> void:
	body.add_child(UIKit.header(t("nav.reports"), 1))
	if app.params.has("open") and opened == "":
		opened = str(app.params["open"])
	var msg := UIKit.label(message)
	msg.name = "reports_msg"
	body.add_child(msg)
	var search := UIKit.line_edit(query, t("library.search"))
	search.text_submitted.connect(func(s: String): query = s; refresh())
	body.add_child(search)
	body.add_child(UIKit.header(t("reports.saved"), 2))
	for e in app.reports.list({"query": query}):
		var open_b := UIKit.button("%s · %s" % [e["id"], e["title"]], func(): opened = str(e["id"]); refresh())
		open_b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		open_b.name = "open_" + str(e["id"])
		body.add_child(open_b)
	body.add_child(UIKit.header(t("reports.battles"), 2))
	for b in app.reports.battles():
		var rep := UIKit.button(t("reports.make_report"), func(): _result(app.reports.from_battle(str(b["id"]))))
		var play := UIKit.button(t("reports.replay"), func(): _replay(str(b["id"])))
		play.name = "replay_" + str(b["id"])
		var exp := UIKit.button(t("reports.export_bundle"), func(): _bundle("battles", str(b["id"])))
		body.add_child(UIKit.row([UIKit.label("%s · %s · %s" % [b["id"], b["title"], b["meta"].get("outcome", "")]), play, rep, exp]))
	body.add_child(UIKit.header(t("reports.batches"), 2))
	for l in app.reports.batches():
		var rep2 := UIKit.button(t("reports.make_report"), func(): _result(app.reports.from_batch(str(l["id"]))))
		body.add_child(UIKit.row([UIKit.label("%s · %s · %s/%s" % [l["id"], l["title"], l["meta"].get("executed", ""), l["meta"].get("total_jobs", "")]), rep2]))
	if opened != "" and app.storage.reports.has(opened):
		_show_report(opened)


func _result(r: Dictionary) -> void:
	message = t("reports.created", [str(r["id"])]) if bool(r["ok"]) else str(r["error"])
	if bool(r["ok"]):
		opened = str(r["id"])
	refresh()


func _replay(id: String) -> void:
	var v := ViewerModel.from_battle(app, id)
	if bool(v["ok"]):
		app.viewer = v["viewer"]
		app.go("viewer")
	else:
		message = "; ".join(v["errors"])
		refresh()


func _bundle(store: String, id: String) -> void:
	var path := app.storage.root.path_join("exports/%s_%s.simbundle" % [store, id])
	var r := BundleIO.export_records(app.storage, [{"store": store, "id": id}], path)
	message = t("reports.exported", [ProjectSettings.globalize_path(path)]) if bool(r["ok"]) else "; ".join(r["errors"])
	refresh()


func _show_report(id: String) -> void:
	body.add_child(HSeparator.new())
	var entry := app.storage.reports.entry(id)
	body.add_child(UIKit.header("%s · %s" % [id, entry["title"]], 2))
	var verr := app.reports.verify(id)
	body.add_child(UIKit.label(t("reports.verified_ok")) if verr.is_empty() else UIKit.error(t("reports.verified_bad", [str(verr)])))
	var exp := UIKit.button(t("reports.export_files"), func():
		var r := app.reports.export_files(id, app.storage.root.path_join("exports"))
		message = t("reports.exported", [", ".join(r["paths"].map(func(p): return ProjectSettings.globalize_path(p)))]) if r["errors"].is_empty() else "; ".join(r["errors"])
		refresh())
	exp.name = "export_btn"
	var del := UIKit.button(t("reports.delete"), func():
		var err := app.reports.delete(id)
		message = err if err != "" else t("reports.deleted")
		opened = ""
		refresh())
	body.add_child(UIKit.row([exp, del]))
	var rv := ReportView.new()
	rv.name = "report_view"
	rv.show_document(app.reports.document(id))
	body.add_child(rv)
