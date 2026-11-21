class_name LibraryScreen
extends BaseScreen
## Biblioteca de contenido: busqueda, filtro por tipo, versiones y detalle (con coste y validacion).

var query: String = ""
var type_filter: String = ""
var selected_id: String = ""
var selected_version: String = ""
var detail_box: VBoxContainer
var history_box: VBoxContainer


func build() -> void:
	body.add_child(UIKit.header(t("nav.library"), 1))
	var search := UIKit.line_edit(query, t("library.search"))
	search.text_submitted.connect(func(s: String): query = s; refresh())
	var types := UIKit.option(["", "character", "abilities", "ai"], type_filter)
	types.item_selected.connect(func(i: int): type_filter = ["", "character", "abilities", "ai"][i]; refresh())
	body.add_child(UIKit.row([search, types, UIKit.button(t("library.import"), func(): app.go("import"))]))
	var entries := app.library.entries({"query": query, "type": type_filter})
	if entries.is_empty():
		body.add_child(UIKit.note(t("library.empty")))
		var ex := UIKit.button(t("library.install_examples"), func():
			var r := app.install_examples()
			selected_id = ""
			refresh()
			if not (r["errors"] as Array).is_empty():
				body.add_child(UIKit.error("; ".join(r["errors"]))))
		ex.name = "install_examples_btn"
		body.add_child(ex)
	for e in entries:
		var txt := "%s %s  ·  %s@%s  ·  %s%s" % ["✓" if e["valid"] else "✗", e["name"], e["id"], e["version"], e["type"], "  (" + t("library.latest") + ")" if e["latest"] else ""]
		var b := UIKit.button(txt, func(): _select(str(e["id"]), str(e["version"])))
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.name = "entry_%s_%s" % [str(e["id"]).replace("/", "_"), str(e["version"]).replace(".", "_")]
		body.add_child(b)
	detail_box = UIKit.column()
	body.add_child(detail_box)
	if selected_id != "":
		_show_detail()
	_show_history(not entries.is_empty())


func _show_history(can_export: bool) -> void:
	if can_export:
		var ex := UIKit.button(t("library.export_all"), func():
			var path := app.storage.root.path_join("exports/library.simbundle")
			var r := app.library.export_library(path)
			if bool(r["ok"]):
				history_box.add_child(UIKit.note(t("library.exported", [r["packages"], path])))
			else:
				history_box.add_child(UIKit.error("; ".join(r["errors"]))))
		ex.name = "export_library_btn"
		body.add_child(ex)
	body.add_child(UIKit.header(t("library.history"), 2))
	history_box = UIKit.column()
	history_box.name = "history_box"
	body.add_child(history_box)
	var h := app.library.history(10)
	if h.is_empty():
		history_box.add_child(UIKit.note(t("library.history_empty")))
	for i in range(h.size() - 1, -1, -1):
		history_box.add_child(UIKit.label("#%d  %s  ·  %s  %s" % [h[i]["seq"], h[i]["action"], h[i]["target"], h[i]["detail"]]))


func _select(id: String, version: String) -> void:
	selected_id = id
	selected_version = version
	refresh()


func _show_detail() -> void:
	var d := app.library.detail(selected_id, selected_version)
	detail_box.add_child(UIKit.header("%s@%s" % [selected_id, selected_version], 2))
	if not bool(d["ok"]):
		detail_box.add_child(UIKit.error(t("library.integrity_bad", [str(d["errors"])])))
		return
	var vs: Array = d["versions"]
	var vopt := UIKit.option(vs, selected_version)
	vopt.item_selected.connect(func(i: int): selected_version = vs[i]; refresh())
	detail_box.add_child(UIKit.row([UIKit.label(t("library.versions")), vopt]))
	detail_box.add_child(UIKit.label(t("library.hash", [str(d["hash"]).substr(0, 16)])))
	detail_box.add_child(UIKit.label(t("library.integrity_ok")))
	if d.has("character"):
		var ch: Dictionary = d["character"]
		var row := UIKit.row()
		var tex := TextureRect.new()
		tex.texture = PortraitProvider.texture(str(ch["name"]), app.storage.library.load_package(selected_id, selected_version)["files"])
		tex.custom_minimum_size = Vector2(72, 72)
		tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
		tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		row.add_child(tex)
		row.add_child(UIKit.header(str(ch["name"]), 3))
		detail_box.add_child(row)
		detail_box.add_child(UIKit.table([t("col.stat"), t("col.value")], ch["stats"].keys().map(func(k): return [k, ReportDocument.num(ch["stats"][k])]), [1]))
		detail_box.add_child(UIKit.table([t("col.ability"), t("col.type"), t("col.cost"), t("col.cooldown")],
			ch["abilities"].map(func(a): return [a["id"], a["action_type"], str(a["cost"]), ReportDocument.num(a["cooldown"])])))
		detail_box.add_child(UIKit.label(t("library.ai", [str(ch["ai"].get("type", "default"))])))
		if not (ch["scripts"] as Array).is_empty():
			detail_box.add_child(UIKit.label(t("library.scripts", [", ".join(ch["scripts"])])))
		detail_box.add_child(context_line())
		var cost: Dictionary = d["cost"]
		detail_box.add_child(UIKit.label(t("library.cost", [ReportDocument.num(cost["creation_cost"]), ReportDocument.num(cost["budget"]["points"]), ReportDocument.num(cost["remaining"])])))
		for w in cost["warnings"]:
			if not str(w).begins_with("perfil ilustrativo"):
				detail_box.add_child(UIKit.warn(str(w)))
		for e in cost["errors"]:
			detail_box.add_child(UIKit.error(str(e)))
		detail_box.add_child(UIKit.button(t("library.use_in_duel"), func():
			app.duel.add_package(selected_id, selected_version)
			app.go("duel")))
	if not (d["used_by"] as Array).is_empty():
		detail_box.add_child(UIKit.note(t("library.used_by", [", ".join(d["used_by"].map(func(r): return "%s/%s" % [r["store"], r["id"]]))])))
	var msg := UIKit.label("")
	msg.name = "remove_msg"
	detail_box.add_child(UIKit.button(t("library.remove"), func():
		var err := app.library.remove(selected_id, selected_version)
		if err == "":
			selected_id = ""
			refresh()
		else:
			msg.text = err))
	detail_box.add_child(msg)
