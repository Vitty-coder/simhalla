class_name ContentLibrary
extends RefCounted
## Biblioteca persistente de paquetes validados (fase 2).
##
## Layout: <root>/<namespace>/<nombre>/<version>/<archivos del paquete> mas
## `.simhalla_hash`. Las versiones son INMUTABLES: no se sobrescribe contenido
## necesario para reproducir combates antiguos. Importar el mismo id@version con
## contenido distinto es un error; con el mismo contenido es idempotente.
## Al leer se recalcula la huella (deteccion de manipulacion).
## Indices, historial y exportacion portable avanzados: fase 9.

const HASH_FILE := ".simhalla_hash"

var root: String


func _init(root_dir: String = "user://library") -> void:
	root = root_dir


func entry_dir(id: String, version: String) -> String:
	return root.path_join(id).path_join(version)


func _dirs(path: String) -> Array:
	var d := DirAccess.open(path)
	if d == null:
		return []
	var out: Array = d.get_directories()
	out.sort()
	return out


## [{id, version, type, hash}] ordenado por id y version.
func list() -> Array:
	var out: Array = []
	for ns in _dirs(root):
		for nm in _dirs(root.path_join(ns)):
			var id := "%s/%s" % [ns, nm]
			for v in versions(id):
				var e := entry(id, v)
				if not e.is_empty():
					out.append(e)
	return out


func versions(id: String) -> Array:
	var vs: Array = []
	for v in _dirs(root.path_join(id)):
		if SemVer.is_valid(v):
			vs.append(v)
	vs.sort_custom(func(a, b): return SemVer.compare(a, b) < 0)
	return vs


func has(id: String, version: String) -> bool:
	return FileAccess.file_exists(entry_dir(id, version).path_join(HASH_FILE))


func entry(id: String, version: String) -> Dictionary:
	if not has(id, version):
		return {}
	var dir := entry_dir(id, version)
	var h := FileAccess.open(dir.path_join(HASH_FILE), FileAccess.READ)
	var m := FileAccess.open(dir.path_join("manifest.json"), FileAccess.READ)
	if h == null or m == null:
		return {}
	var manifest: Variant = JSON.parse_string(m.get_as_text())
	if not (manifest is Dictionary):
		return {}
	return {"id": id, "version": version, "type": str(manifest.get("type", "")), "hash": h.get_as_text().strip_edges()}


## Version mas alta que cumple la restriccion ({} si ninguna). Ignora prereleases
## salvo que la restriccion incluya un guion (p. ej. "2.1.0-beta").
func resolve(id: String, constraint: String) -> Dictionary:
	var vs := versions(id)
	vs.reverse()
	for v in vs:
		# Las prereleases solo se resuelven si la restriccion las menciona expresamente.
		if SemVer.parse(v)[3] != "" and not constraint.contains("-"):
			continue
		if SemVer.satisfies(v, constraint):
			return entry(id, v)
	return {}


## Guarda un paquete ya validado. Devuelve "" (ok / ya presente identico) o error.
func store(files: Dictionary, id: String, version: String, hash: String) -> String:
	if has(id, version):
		var e := entry(id, version)
		if e.get("hash", "") == hash:
			return ""
		return "[version_conflicto] %s@%s ya existe con contenido distinto; publique una version nueva" % [id, version]
	var final_dir := entry_dir(id, version)
	var tmp := root.path_join(".tmp_" + hash.substr(0, 16))
	DirAccess.make_dir_recursive_absolute(tmp)
	for rel in files:
		var path: String = tmp.path_join(rel)
		DirAccess.make_dir_recursive_absolute(path.get_base_dir())
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_remove_tree(tmp)
			return "[escritura] no se pudo escribir '%s'" % rel
		f.store_buffer(files[rel])
		f.close()
	var hf := FileAccess.open(tmp.path_join(HASH_FILE), FileAccess.WRITE)
	hf.store_string(hash)
	hf.close()
	DirAccess.make_dir_recursive_absolute(final_dir.get_base_dir())
	if DirAccess.rename_absolute(tmp, final_dir) != OK:
		_remove_tree(tmp)
		return "[escritura] no se pudo finalizar la importacion de %s@%s" % [id, version]
	return ""


static func _remove_tree(path: String) -> void:
	var d := DirAccess.open(path)
	if d == null:
		return
	for sub in d.get_directories():
		_remove_tree(path.path_join(sub))
	d.include_hidden = true
	for f in d.get_files():
		d.remove(f)
	DirAccess.remove_absolute(path)


## Elimina UNA version (la proteccion contra referencias vive en AppStorage.remove_package). Devuelve "" o error.
func remove(id: String, version: String) -> String:
	if not has(id, version):
		return "[no_encontrado] %s@%s no esta en la biblioteca" % [id, version]
	_remove_tree(entry_dir(id, version))
	var parent := root.path_join(id)
	if _dirs(parent).is_empty():
		DirAccess.remove_absolute(parent)
		var ns := parent.get_base_dir()
		if _dirs(ns).is_empty():
			DirAccess.remove_absolute(ns)
	return ""


## Borra la biblioteca completa (solo pruebas/mantenimiento).
func destroy() -> void:
	_remove_tree(root)


## Carga un paquete almacenado: {"manifest","parsed":{archivo:json},"files","hash","errors"}.
func load_package(id: String, version: String) -> Dictionary:
	var out := {"manifest": {}, "parsed": {}, "files": {}, "hash": "", "errors": []}
	if not has(id, version):
		out["errors"].append("[no_encontrado] %s@%s no esta en la biblioteca" % [id, version])
		return out
	var src := PackageSource._read_dir(entry_dir(id, version))
	var files: Dictionary = src["files"]
	out["errors"].append_array(src["errors"])
	var expected: String = entry(id, version).get("hash", "")
	var actual := PackageSource.content_hash(files)
	if actual != expected:
		out["errors"].append("[integridad] %s@%s: la huella no coincide (esperada %s, actual %s); contenido alterado" % [id, version, expected.substr(0, 12), actual.substr(0, 12)])
		return out
	out["files"] = files
	out["hash"] = actual
	for rel in files:
		if str(rel).ends_with(".json"):
			var p: Variant = JSON.parse_string((files[rel] as PackedByteArray).get_string_from_utf8())
			if p == null:
				out["errors"].append("[json] %s@%s: '%s' no es JSON valido" % [id, version, rel])
			else:
				var mig: Dictionary = SchemaMigrator.default().migrate(p) if p is Dictionary else {"ok": true, "data": p, "errors": []}
				if bool(mig["ok"]):
					out["parsed"][rel] = mig["data"]
				else:
					out["errors"].append("%s@%s: %s: %s" % [id, version, rel, "; ".join(mig["errors"])])
	out["manifest"] = out["parsed"].get("manifest.json", {})
	return out


## Construye una CombatEntity desde un paquete de personaje almacenado.
## Devuelve {"entity", "errors", "warnings", "content_ref"}.
func build_entity(id: String, constraint: String, rules: Ruleset, profile: BalanceProfile, registry: OperationRegistry, overrides: Dictionary = {}, patch: Dictionary = {}) -> Dictionary:
	var e := resolve(id, constraint)
	if e.is_empty():
		return {"entity": null, "errors": ["[no_encontrado] ningun paquete '%s' cumple '%s'" % [id, constraint]], "warnings": [], "content_ref": {}}
	var pkg := load_package(id, e["version"])
	if not pkg["errors"].is_empty():
		return {"entity": null, "errors": pkg["errors"], "warnings": [], "content_ref": {}}
	if str(pkg["manifest"].get("type", "")) != "character":
		return {"entity": null, "errors": ["[tipo] %s@%s no es un paquete de personaje" % [id, e["version"]]], "warnings": [], "content_ref": {}}
	var comp := EntityComposer.compose(pkg["parsed"], pkg["manifest"], self, PackageSource.scripts_of(pkg["files"]))
	if not comp["errors"].is_empty():
		return {"entity": null, "errors": comp["errors"], "warnings": comp["warnings"], "content_ref": {}}
	var ref := {"id": id, "version": e["version"], "hash": pkg["hash"], "dependencies": comp["deps"]}
	var data: Dictionary = comp["data"]
	for k in overrides:
		data[k] = overrides[k]
	if not patch.is_empty():
		data = Ruleset._merge(data, patch) # fusion profunda (variaciones controladas de parametros)
	var b := EntityFactory.build(data, profile, rules, registry)
	if b["entity"] != null:
		(b["entity"] as CombatEntity).content_ref = ref
	return {"entity": b["entity"], "errors": b["errors"], "warnings": comp["warnings"] + b["warnings"], "content_ref": ref, "data": data}
