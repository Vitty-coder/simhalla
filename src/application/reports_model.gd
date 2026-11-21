class_name ReportsModel
extends RefCounted
## Modelo de la pantalla Informes: lista (con busqueda), apertura en los tres formatos, documento nativo para la interfaz,
## verificacion, exportacion a archivos, borrado protegido y generacion desde combates/lotes guardados.

var app: AppController


func _init(a: AppController) -> void:
	app = a


func list(filter: Dictionary = {}) -> Array:
	var out: Array = app.storage.reports.list(filter)
	out.reverse() # mas recientes primero
	return out


func open(id: String, fmt: String = "md") -> String:
	var name: String = {"md": "report.md", "json": "report.json", "html": "report.html"}.get(fmt, "report.md")
	return app.storage.reports.read_text(id, name)


func model(id: String) -> Dictionary:
	var m: Variant = app.storage.reports.read_json(id, "report.json")
	return m if m is Dictionary else {}


## Documento (bloques) para que la interfaz lo pinte de forma nativa.
func document(id: String) -> ReportDocument:
	return ReportDocument.from_model(model(id))


func verify(id: String) -> Array:
	return app.storage.verify_report(id)


func export_files(id: String, dir: String) -> Dictionary:
	var m := model(id)
	if m.is_empty():
		return {"paths": [], "errors": ["informe no legible"]}
	return ReportExporter.write_all(m, dir, "informe_%s" % id)


func delete(id: String) -> String:
	return app.storage.remove_record("reports", id)


## Informe de un combate guardado (se reproduce y se verifica antes). {"ok","id","error"}.
func from_battle(battle_id: String) -> Dictionary:
	var v := ViewerModel.from_battle(app, battle_id)
	if not bool(v["ok"]):
		return {"ok": false, "id": "", "error": "; ".join(v["errors"])}
	var vm: ViewerModel = v["viewer"]
	return vm.save_report(battle_id, "Informe del combate %s" % battle_id)


func from_batch(batch_id: String) -> Dictionary:
	var lb := app.storage.load_batch(batch_id)
	if not bool(lb["ok"]):
		return {"ok": false, "id": "", "error": str(lb["error"])}
	var m := BatchReport.build(lb["result"])
	return app.storage.save_report(m, "Informe del lote %s" % batch_id, [{"kind": "batch", "id": batch_id}])


func battles() -> Array:
	var out: Array = app.storage.battles.list()
	out.reverse()
	return out


func batches() -> Array:
	var out: Array = app.storage.batches.list()
	out.reverse()
	return out
