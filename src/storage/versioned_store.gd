class_name VersionedStore
extends RefCounted
## Almacen persistente de elementos JSON VERSIONADOS e INMUTABLES (reglamentos, perfiles de equilibrio, configuraciones de
## simulacion...). Layout: <root>/<namespace>/<nombre>/<version>/data.json + .hash (SHA-256 del JSON canonico).
## Mismo id@version con contenido distinto = colision EXPLICITA (nunca se sobrescribe lo necesario para reproducir batallas
## antiguas): se rechaza, o se guarda como version nueva (`put_resolving`). Al leer se recalcula la huella (manipulacion).
## `validator`: Callable(data) -> Array de errores (opcional). Los ids son `namespace/nombre` (minusculas, digitos y _).

const HASH_FILE := ".simhalla_hash"
const DATA_FILE := "data.json"
const ID_RE := "^[a-z][a-z0-9_]{0,31}/[a-z][a-z0-9_]{0,63}$"

var root: String
var validator: Callable = Callable()
var kind: String = ""


func _init(root_dir: String, kind_name: String, validate_fn: Callable = Callable()) -> void:
	root = root_dir
	kind = kind_name
	validator = validate_fn


static func canonical_hash(data: Dictionary) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(JSON.stringify(ReportExporter._norm(data), "", true, true).to_utf8_buffer())
	return h.finish().hex_encode()


func _dir(id: String, version: String) -> String:
	return root.path_join(id).path_join(version)


func _dirs(path: String) -> Array:
	var d := DirAccess.open(path)
	if d == null:
		return []
	var out: Array = d.get_directories()
	out.sort()
	return out


func versions(id: String) -> Array:
	var vs: Array = []
	for v in _dirs(root.path_join(id)):
		if SemVer.is_valid(v):
			vs.append(v)
	vs.sort_custom(func(a, b): return SemVer.compare(a, b) < 0)
	return vs


## [{id, version, hash}] ordenado.
func list() -> Array:
	var out: Array = []
	for ns in _dirs(root):
		for nm in _dirs(root.path_join(ns)):
			var id := "%s/%s" % [ns, nm]
			for v in versions(id):
				var h := _read_hash(id, v)
				if h != "":
					out.append({"id": id, "version": v, "hash": h})
	return out


func _read_hash(id: String, version: String) -> String:
	var f := FileAccess.open(_dir(id, version).path_join(HASH_FILE), FileAccess.READ)
	return f.get_as_text().strip_edges() if f != null else ""


func has(id: String, version: String) -> bool:
	return _read_hash(id, version) != ""


## Guarda id@version. {"ok", "status": "stored"|"already_present", "error"}.
func put(id: String, version: String, data: Dictionary) -> Dictionary:
	if not RegEx.create_from_string(ID_RE).search(id):
		return {"ok": false, "status": "", "error": "[id] '%s' no es valido (use namespace/nombre en minusculas)" % id}
	if not SemVer.is_valid(version):
		return {"ok": false, "status": "", "error": "[version] '%s' no es una version semver valida" % version}
	if validator.is_valid():
		var errs: Array = validator.call(data)
		if not errs.is_empty():
			return {"ok": false, "status": "", "error": "[validacion] " + "; ".join(errs.map(func(e): return str(e)))}
	var h := canonical_hash(data)
	if has(id, version):
		if _read_hash(id, version) == h:
			return {"ok": true, "status": "already_present", "error": ""}
		return {"ok": false, "status": "", "error": "[colision] %s@%s ya existe con contenido distinto; use otra version (put_resolving) o conserve la existente" % [id, version]}
	var dir := _dir(id, version)
	DirAccess.make_dir_recursive_absolute(dir)
	var f := FileAccess.open(dir.path_join(DATA_FILE), FileAccess.WRITE)
	if f == null:
		return {"ok": false, "status": "", "error": "[escritura] no se pudo escribir %s@%s" % [id, version]}
	f.store_string(JSON.stringify(data, "  ", true, true))
	f.close()
	var hf := FileAccess.open(dir.path_join(HASH_FILE), FileAccess.WRITE)
	hf.store_string(h)
	hf.close()
	return {"ok": true, "status": "stored", "error": ""}


## Politica de colision "version nueva": si id@version existe con otro contenido, guarda en la siguiente version de parche libre.
## Devuelve {"ok", "status", "version", "error"}.
func put_resolving(id: String, version: String, data: Dictionary) -> Dictionary:
	var v := version
	var guard := 0
	while guard < 1000:
		guard += 1
		var r := put(id, v, data)
		if bool(r["ok"]) or not str(r["error"]).begins_with("[colision]"):
			r["version"] = v
			return r
		var p := SemVer.parse(v)
		v = "%d.%d.%d" % [p[0], p[1], int(p[2]) + 1]
	return {"ok": false, "status": "", "version": version, "error": "[colision] no se encontro una version libre"}


## Lee y VERIFICA la huella. {"ok", "data", "hash", "error"}.
func get_item(id: String, version: String) -> Dictionary:
	if not has(id, version):
		return {"ok": false, "data": {}, "hash": "", "error": "[no_encontrado] %s@%s" % [id, version]}
	var f := FileAccess.open(_dir(id, version).path_join(DATA_FILE), FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if not (parsed is Dictionary):
		return {"ok": false, "data": {}, "hash": "", "error": "[json] %s@%s no se puede leer" % [id, version]}
	var h := canonical_hash(parsed)
	if h != _read_hash(id, version):
		return {"ok": false, "data": {}, "hash": h, "error": "[integridad] %s@%s: la huella no coincide (contenido alterado)" % [id, version]}
	return {"ok": true, "data": parsed, "hash": h, "error": ""}


## Version mas alta que cumple la restriccion ("*" = la mas alta). {} si ninguna.
func resolve(id: String, constraint: String = "*") -> Dictionary:
	var vs := versions(id)
	vs.reverse()
	for v in vs:
		if SemVer.parse(v)[3] != "" and not constraint.contains("-"):
			continue
		if SemVer.satisfies(v, constraint):
			return {"id": id, "version": v, "hash": _read_hash(id, v)}
	return {}


## Version mas alta de todas (incluidas las prereleases, como "0.1.0-provisional"). {} si no hay.
func latest(id: String) -> Dictionary:
	var vs := versions(id)
	if vs.is_empty():
		return {}
	return {"id": id, "version": vs.back(), "hash": _read_hash(id, vs.back())}


func remove(id: String, version: String) -> String:
	if not has(id, version):
		return "[no_encontrado] %s@%s" % [id, version]
	ContentLibrary._remove_tree(_dir(id, version))
	var parent := root.path_join(id)
	if _dirs(parent).is_empty():
		DirAccess.remove_absolute(parent)
		var ns := parent.get_base_dir()
		if _dirs(ns).is_empty():
			DirAccess.remove_absolute(ns)
	return ""
