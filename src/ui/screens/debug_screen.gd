class_name DebugScreen
extends BaseScreen
## Depuracion avanzada (canal separado de la vista limitada de la IA): estado interno de una entidad (estadisticas con modificadores,
## variables de scripts, memoria de IA), estados del RNG, tiradas, filtros de eventos y diagnostico de abortos.

var entity_id: String = ""
var type_filter: String = ""


func build() -> void:
	body.add_child(UIKit.header(t("nav.debug"), 1))
	var vm := app.viewer
	if vm == null:
		body.add_child(UIKit.note(t("viewer.none")))
		return
	var dbg := vm.debug()
	var ids: Array = vm.session.engine.entities.map(func(e): return e.id)
	if entity_id == "" or not ids.has(entity_id):
		entity_id = str(ids[0]) if not ids.is_empty() else ""
	var opt := UIKit.option(ids, entity_id)
	opt.name = "debug_entity"
	opt.item_selected.connect(func(i: int): entity_id = ids[i]; refresh())
	body.add_child(UIKit.row([UIKit.label(t("debug.entity")), opt]))
	var st := dbg.entity_state(entity_id)
	var txt := TextEdit.new()
	txt.name = "debug_state"
	txt.editable = false
	txt.custom_minimum_size.y = 220
	txt.text = JSON.stringify(st, "  ", true)
	body.add_child(txt)
	body.add_child(UIKit.header(t("debug.rng"), 3))
	body.add_child(UIKit.label(str(dbg.rng_states())))
	var tf := UIKit.line_edit(type_filter, t("debug.type_filter"))
	tf.text_submitted.connect(func(s: String): type_filter = s; refresh())
	body.add_child(tf)
	var f := {"entity": entity_id, "limit": 40}
	if type_filter != "":
		f["type"] = type_filter
	body.add_child(UIKit.header(t("debug.events"), 3))
	body.add_child(UIKit.table(["#", "t", t("col.type"), t("col.from"), t("col.to")], dbg.filter_events(f).map(func(e): return [e["id"], ReportDocument.num(float(e["time"]) / float(Ruleset.TIME_SCALE), 1), e["type"], e["source"], e["target"]])))
	body.add_child(UIKit.header(t("debug.rolls"), 3))
	body.add_child(UIKit.table([t("col.type"), "chance", "roll", t("col.result")], dbg.rolls(entity_id).slice(0, 30).map(func(r): return [r["type"], ReportDocument.num(r["chance"]), ReportDocument.num(r["roll"]), ReportDocument.num(r["success"])])))
	var diag := dbg.abort_diagnostic()
	if not diag.is_empty():
		body.add_child(UIKit.error(t("debug.aborted", [str(diag["error"])])))
