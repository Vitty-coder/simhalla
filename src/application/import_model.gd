class_name ImportModel
extends RefCounted
## Modelo de la pantalla Importacion/validacion: vista previa SIN almacenar (errores por archivo y ruta, avisos, dependencias,
## coste de creacion y presupuesto segun el modo), deteccion explicita de colisiones de version y confirmacion.
## Importar nunca ejecuta scripts.

var app: AppController
var last_report: ImportReport = null
var last_path: String = ""


func _init(a: AppController) -> void:
	app = a


func _importer(mode_override: String = "") -> PackageImporter:
	var imp := PackageImporter.new(app.storage.library, app.ruleset())
	var prof := app.profile()
	if prof.has_costs():
		imp.balance = {"profile": prof, "mode": mode_override if mode_override != "" else app.mode(), "budget": app.budget()}
	return imp


## Valida sin almacenar. {"ok", "report", "errors", "warnings", "balance", "collision": {"exists", "same", "next_version"}}.
func preview(path: String) -> Dictionary:
	last_path = path
	var rep := _importer().validate(path)
	last_report = rep
	var col := {"exists": false, "same": false, "next_version": ""}
	if rep.id != "" and rep.version != "" and app.storage.library.has(rep.id, rep.version):
		col["exists"] = true
		col["same"] = str(app.storage.library.entry(rep.id, rep.version)["hash"]) == rep.hash
		var p := SemVer.parse(rep.version)
		if not p.is_empty():
			var v := "%d.%d.%d" % [p[0], p[1], int(p[2]) + 1]
			while app.storage.library.has(rep.id, v):
				p = SemVer.parse(v)
				v = "%d.%d.%d" % [p[0], p[1], int(p[2]) + 1]
			col["next_version"] = v
	return {"ok": rep.ok() and not (bool(col["exists"]) and not bool(col["same"])), "report": rep, "errors": rep.errors, "warnings": rep.warnings, "balance": rep.balance,
		"id": rep.id, "version": rep.version, "type": rep.type, "hash": rep.hash, "collision": col}


## Importa. policy ante colision con contenido distinto: "reject" (por defecto) | "new_version" (se guarda como la siguiente version).
func commit(path: String, policy: String = "reject") -> Dictionary:
	var pv := preview(path)
	var col: Dictionary = pv["collision"]
	if not (pv["report"] as ImportReport).ok():
		return {"ok": false, "errors": pv["errors"], "id": pv["id"], "version": pv["version"], "stored": false}
	if bool(col["exists"]) and not bool(col["same"]):
		if policy != "new_version":
			return {"ok": false, "errors": ["[version_conflicto] %s@%s ya existe con contenido distinto: elija 'version nueva' (%s) o conserve la existente" % [pv["id"], pv["version"], col["next_version"]]],
				"id": pv["id"], "version": pv["version"], "stored": false}
		return _commit_as_new_version(path, str(col["next_version"]))
	var rep := _importer().import_package(path)
	if rep.ok() and rep.stored:
		app.storage.log_event("import", "%s@%s" % [rep.id, rep.version], rep.hash)
	return {"ok": rep.ok(), "errors": rep.errors, "id": rep.id, "version": rep.version, "stored": rep.stored, "already_present": rep.already_present}


## Reescribe el manifiesto con la version nueva y la importa (el original no se toca).
func _commit_as_new_version(path: String, new_version: String) -> Dictionary:
	var src := PackageSource.read(path)
	var files: Dictionary = src["files"]
	var man: Variant = JSON.parse_string((files["manifest.json"] as PackedByteArray).get_string_from_utf8())
	if not (man is Dictionary):
		return {"ok": false, "errors": ["manifest.json ilegible"], "stored": false}
	man["version"] = new_version
	files["manifest.json"] = JSON.stringify(man, "  ").to_utf8_buffer()
	var tmp := app.storage.root.path_join(".tmp/newver_%d" % Time.get_ticks_usec())
	for rel in files:
		var p: String = tmp.path_join(rel)
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_buffer(files[rel])
		f.close()
	var rep := _importer().import_package(tmp)
	ContentLibrary._remove_tree(tmp)
	if rep.ok() and rep.stored:
		app.storage.log_event("import", "%s@%s" % [rep.id, rep.version], "version nueva: " + rep.hash)
	return {"ok": rep.ok(), "errors": rep.errors, "id": rep.id, "version": rep.version, "stored": rep.stored, "renamed_from": str(man.get("version", ""))}
