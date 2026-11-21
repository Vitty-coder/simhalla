class_name ImportScreen
extends BaseScreen
## Importacion y validacion: vista previa sin almacenar (errores por archivo/ruta, avisos, coste), colision de version explicita.

var path_edit: LineEdit
var preview: Dictionary = {}
var result_msg: String = ""
var result_ok: bool = true


func build() -> void:
	body.add_child(UIKit.header(t("nav.import"), 1))
	body.add_child(UIKit.note(t("import.hint")))
	path_edit = UIKit.line_edit(app.importer.last_path, t("import.path_placeholder"))
	path_edit.name = "path_edit"
	body.add_child(path_edit)
	var browse := UIKit.button(t("import.browse"), func():
		var used := FilePicker.open(self, func(p: String): path_edit.text = p; refresh_with_path(p))
		if used == "inbox":
			result_msg = t("import.inbox_only", [ProjectSettings.globalize_path(FilePicker.ensure_inbox(app.storage.root))])
			result_ok = true
			refresh())
	browse.name = "browse_btn"
	body.add_child(browse)
	_show_inbox()
	var vb := UIKit.button(t("import.validate"), func(): _validate())
	vb.name = "validate_btn"
	body.add_child(vb)
	if not preview.is_empty():
		_show_preview()
	if result_msg != "":
		body.add_child(UIKit.label(result_msg) if result_ok else UIKit.error(result_msg))


func refresh_with_path(p: String) -> void:
	app.importer.last_path = p
	_validate()


func _validate() -> void:
	result_msg = ""
	if FilePicker.classify(path_edit.text) == "bundle":
		preview = {}
		var r := BundleIO.import_bundle(app.storage, path_edit.text)
		result_ok = bool(r["ok"])
		result_msg = t("import.bundle_done", [r["packages"].size(), r["records"].size()]) if result_ok else "; ".join(r["errors"])
		for w in r.get("warnings", []):
			result_msg += "\n" + str(w)
	else:
		preview = app.importer.preview(path_edit.text)
	refresh()


## Bandeja de entrada: archivos dejados en la carpeta de la aplicacion (via garantizada en moviles).
func _show_inbox() -> void:
	var items := FilePicker.list_inbox(app.storage.root)
	body.add_child(UIKit.note(t("import.inbox", [ProjectSettings.globalize_path(FilePicker.inbox_dir(app.storage.root))])))
	for it in items:
		var b := UIKit.button("%s  (%s)" % [it["name"], it["kind"]], func(): path_edit.text = str(it["path"]); _validate())
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.name = "inbox_" + str(it["name"]).replace(".", "_")
		body.add_child(b)


func _show_preview() -> void:
	var rep: ImportReport = preview["report"]
	body.add_child(UIKit.header(t("import.result"), 2))
	if rep.id != "":
		body.add_child(UIKit.label("%s@%s · %s · %s" % [rep.id, rep.version, rep.type, rep.hash.substr(0, 16)]))
	for e in preview["errors"]:
		body.add_child(UIKit.error(str(e)))
	for w in preview["warnings"]:
		body.add_child(UIKit.warn(str(w)))
	if not (preview["balance"] as Dictionary).is_empty():
		var b: Dictionary = preview["balance"]
		body.add_child(context_line())
		body.add_child(UIKit.label(t("import.cost", [ReportDocument.num(b["creation_cost"]), ReportDocument.num(b["budget"]["points"]), ReportDocument.num(b["remaining"])])))
	var col: Dictionary = preview["collision"]
	if bool(col["exists"]) and not bool(col["same"]):
		body.add_child(UIKit.warn(t("import.collision", [str(col["next_version"])])))
		var nb := UIKit.button(t("import.as_new_version", [str(col["next_version"])]), func(): _commit("new_version"))
		nb.name = "new_version_btn"
		body.add_child(nb)
	elif bool(col["exists"]):
		body.add_child(UIKit.note(t("import.already_present")))
	if rep.ok() and not (bool(col["exists"]) and not bool(col["same"])):
		var ib := UIKit.button(t("import.confirm"), func(): _commit("reject"))
		ib.name = "import_btn"
		body.add_child(ib)


func _commit(policy: String) -> void:
	var r := app.importer.commit(path_edit.text, policy)
	result_ok = bool(r["ok"])
	result_msg = t("import.done", [str(r.get("id", "")), str(r.get("version", ""))]) if result_ok else "; ".join(r["errors"])
	preview = {}
	refresh()
