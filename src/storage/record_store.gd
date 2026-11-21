class_name RecordStore
extends RefCounted
## Almacen de REGISTROS inmutables con historial (combates guardados, lotes, informes). Cada registro tiene un id secuencial
## (`<prefijo>NNNN`, sin reloj: determinista), archivos con nombre, huella de contenido, referencias a otros elementos
## (paquetes con version y huella, combates, lotes...) y metadatos libres. Layout: <root>/<id>/<archivos> + index.json (indice local).
## Los registros no se sobrescriben; `remove` se rechaza mientras otro registro dependa de el (`[referenciado]`).
## El instante de guardado (`saved_at`) es solo metadato informativo y NO entra en la huella.

const INDEX_FILE := "index.json"
const MAX_FILE_BYTES := 64 * 1024 * 1024

var root: String
var prefix: String
var kind: String


func _init(root_dir: String, id_prefix: String, kind_name: String) -> void:
	root = root_dir
	prefix = id_prefix
	kind = kind_name


func _index() -> Dictionary:
	var f := FileAccess.open(root.path_join(INDEX_FILE), FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if parsed is Dictionary and parsed.has("entries"):
		return SchemaMigrator.default().upgraded(parsed)
	return {"schema": "simhalla.records/1", "kind": kind, "next": 1, "entries": []}


func _save_index(idx: Dictionary) -> bool:
	DirAccess.make_dir_recursive_absolute(root)
	var tmp := root.path_join(INDEX_FILE + ".tmp")
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(JSON.stringify(idx, "  ", true, true))
	f.close()
	if FileAccess.file_exists(root.path_join(INDEX_FILE)):
		DirAccess.remove_absolute(root.path_join(INDEX_FILE))
	return DirAccess.rename_absolute(tmp, root.path_join(INDEX_FILE)) == OK


static func files_hash(files: Dictionary) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	var names: Array = files.keys()
	names.sort()
	for n in names:
		var b: PackedByteArray = files[n] if files[n] is PackedByteArray else str(files[n]).to_utf8_buffer()
		h.update(("%s:%d\n" % [n, b.size()]).to_utf8_buffer())
		h.update(b)
	return h.finish().hex_encode()


## Anade un registro. files: {nombre: texto|bytes}. refs: [{kind, id, version?, hash?}]. {"ok","id","hash","error"}.
func add(title: String, files: Dictionary, refs: Array = [], meta: Dictionary = {}, record_kind: String = "") -> Dictionary:
	for n in files:
		if not RegEx.create_from_string("^[A-Za-z0-9_.-]{1,80}$").search(str(n)):
			return {"ok": false, "id": "", "hash": "", "error": "[nombre] archivo no valido '%s'" % str(n)}
		var sz: int = (files[n] as PackedByteArray).size() if files[n] is PackedByteArray else str(files[n]).to_utf8_buffer().size()
		if sz > MAX_FILE_BYTES:
			return {"ok": false, "id": "", "hash": "", "error": "[tamano] '%s' supera %d bytes" % [str(n), MAX_FILE_BYTES]}
	var idx := _index()
	var seq := int(idx["next"])
	var id := "%s%04d" % [prefix, seq]
	var dir := root.path_join(id)
	DirAccess.make_dir_recursive_absolute(dir)
	for n in files:
		var f := FileAccess.open(dir.path_join(str(n)), FileAccess.WRITE)
		if f == null:
			ContentLibrary._remove_tree(dir)
			return {"ok": false, "id": "", "hash": "", "error": "[escritura] no se pudo escribir '%s'" % str(n)}
		if files[n] is PackedByteArray:
			f.store_buffer(files[n])
		else:
			f.store_string(str(files[n]))
		f.close()
	var h := files_hash(files)
	var m := meta.duplicate(true)
	m["saved_at"] = Time.get_datetime_string_from_system(true) # informativo; fuera de la huella
	idx["entries"].append({"id": id, "seq": seq, "kind": record_kind if record_kind != "" else kind, "title": title, "hash": h, "files": files.keys(), "refs": refs.duplicate(true), "meta": m})
	idx["next"] = seq + 1
	if not _save_index(idx):
		ContentLibrary._remove_tree(dir)
		return {"ok": false, "id": "", "hash": "", "error": "[escritura] no se pudo actualizar el indice"}
	return {"ok": true, "id": id, "hash": h, "error": ""}


## Entradas del indice (mas antiguas primero). filter: {kind?, query? (en titulo), ref_id?}.
func list(filter: Dictionary = {}) -> Array:
	var out: Array = []
	for e in _index()["entries"]:
		if filter.has("kind") and str(e["kind"]) != str(filter["kind"]):
			continue
		if str(filter.get("query", "")) != "" and not str(e["title"]).to_lower().contains(str(filter["query"]).to_lower()):
			continue
		if filter.has("ref_id") and not (e["refs"] as Array).any(func(r): return str(r.get("id", "")) == str(filter["ref_id"])):
			continue
		out.append(e)
	return out


func entry(id: String) -> Dictionary:
	for e in _index()["entries"]:
		if str(e["id"]) == id:
			return e
	return {}


func has(id: String) -> bool:
	return not entry(id).is_empty()


func read_file(id: String, name: String) -> PackedByteArray:
	if not has(id) or not (entry(id)["files"] as Array).has(name):
		return PackedByteArray()
	var f := FileAccess.open(root.path_join(id).path_join(name), FileAccess.READ)
	return f.get_buffer(f.get_length()) if f != null else PackedByteArray()


func read_text(id: String, name: String) -> String:
	return read_file(id, name).get_string_from_utf8()


func read_json(id: String, name: String) -> Variant:
	return JSON.parse_string(read_text(id, name))


## Verifica la huella de los archivos de un registro. Devuelve "" o el error.
func verify(id: String) -> String:
	var e := entry(id)
	if e.is_empty():
		return "[no_encontrado] %s" % id
	var files := {}
	for n in e["files"]:
		var f := FileAccess.open(root.path_join(id).path_join(str(n)), FileAccess.READ)
		if f == null:
			return "[integridad] falta el archivo '%s' de %s" % [str(n), id]
		files[n] = f.get_buffer(f.get_length())
	if files_hash(files) != str(e["hash"]):
		return "[integridad] %s: la huella no coincide (contenido alterado)" % id
	return ""


func remove(id: String) -> String:
	var idx := _index()
	var found := -1
	for i in (idx["entries"] as Array).size():
		if str(idx["entries"][i]["id"]) == id:
			found = i
	if found < 0:
		return "[no_encontrado] %s" % id
	(idx["entries"] as Array).remove_at(found)
	if not _save_index(idx):
		return "[escritura] no se pudo actualizar el indice"
	ContentLibrary._remove_tree(root.path_join(id))
	return ""
