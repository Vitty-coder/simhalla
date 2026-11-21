class_name BundleIO
extends RefCounted
## Exportacion/importacion PORTABLE (`.simbundle`, un ZIP): registros (combates, lotes, informes) + los paquetes EXACTOS que
## referencian (version y huella), para llevar un combate a otro dispositivo y reproducirlo alli. Offline, sin servicios.
##
## bundle.json: {schema: "simhalla.bundle/1", engine_version, items:[{store, id, entry}], packages:[{id, version, hash, file}], hashes:{ruta: sha256}}
## Importacion SEGURA: lectura con las defensas de PackageSource (rutas, tamanos, bombas ZIP), verificacion de la huella de cada
## archivo, los paquetes se validan con PackageImporter y su huella debe coincidir con la referencia; los registros se anaden con
## ids NUEVOS (las referencias entre ellos se remapean). Una version de paquete ya existente con contenido distinto es un conflicto
## EXPLICITO (`[version_conflicto]`): nunca se sobrescribe. No se ejecuta nada del bundle.

const SCHEMA := "simhalla.bundle/1"
const STORES := ["battles", "batches", "reports"]


static func _store(s: AppStorage, name: String) -> RecordStore:
	return {"battles": s.battles, "batches": s.batches, "reports": s.reports}.get(name, null)


static func _sha(b: PackedByteArray) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(b)
	return h.finish().hex_encode()


## Zip en memoria de los archivos de un paquete (via archivo temporal en user://).
static func _zip_bytes(files: Dictionary, tmp_dir: String) -> PackedByteArray:
	DirAccess.make_dir_recursive_absolute(tmp_dir)
	var p := tmp_dir.path_join("_pkg_%d.zip" % Time.get_ticks_usec())
	var z := ZIPPacker.new()
	if z.open(p) != OK:
		return PackedByteArray()
	var names: Array = files.keys()
	names.sort()
	for n in names:
		z.start_file(str(n))
		z.write_file(files[n])
		z.close_file()
	z.close()
	var f := FileAccess.open(p, FileAccess.READ)
	var b := f.get_buffer(f.get_length())
	f.close()
	DirAccess.remove_absolute(p)
	return b


## items: [{"store": "battles|batches|reports", "id"}]. {"ok", "errors", "packages": n, "records": n}.
static func export_records(s: AppStorage, items: Array, path: String) -> Dictionary:
	var errs: Array = []
	var entries: Array = []
	var files := {}
	var pkgs := {}
	for it in items:
		var st := _store(s, str(it["store"]))
		if st == null:
			errs.append("almacen desconocido '%s'" % str(it["store"]))
			continue
		var e := st.entry(str(it["id"]))
		if e.is_empty():
			errs.append("[no_encontrado] %s/%s" % [str(it["store"]), str(it["id"])])
			continue
		var verr := st.verify(str(it["id"]))
		if verr != "":
			errs.append(verr)
			continue
		entries.append({"store": it["store"], "id": it["id"], "entry": e})
		for n in e["files"]:
			files["records/%s/%s/%s" % [it["store"], it["id"], n]] = st.read_file(str(it["id"]), str(n))
		for r in e["refs"]:
			if str(r.get("kind", "")) == "package":
				pkgs["%s@%s" % [r["id"], r["version"]]] = r
	if not errs.is_empty():
		return {"ok": false, "errors": errs, "packages": 0, "records": 0}
	var derr := _close_dependencies(s, pkgs)
	if not derr.is_empty():
		return {"ok": false, "errors": derr, "packages": 0, "records": 0}
	var pk := _pack_packages(s, pkgs, files)
	if not (pk["errors"] as Array).is_empty():
		return {"ok": false, "errors": pk["errors"], "packages": 0, "records": 0}
	var pk_list: Array = pk["list"]
	return _write_bundle(s, path, entries, pk_list, files)


## Cierra `pkgs` bajo dependencias (transitivas): un bundle debe poder importarse en una instalacion LIMPIA. Cada dependencia se resuelve con la
## restriccion del manifiesto contra la biblioteca (ultima version que la cumple). Devuelve errores ([] = ok).
static func _close_dependencies(s: AppStorage, pkgs: Dictionary) -> Array:
	var errs: Array = []
	var queue: Array = pkgs.keys()
	var i := 0
	while i < queue.size():
		var k: String = queue[i]
		i += 1
		var r: Dictionary = pkgs[k]
		var lp := s.library.load_package(str(r["id"]), str(r["version"]))
		if not (lp["errors"] as Array).is_empty():
			continue # el error se informa al empaquetar
		for d in (lp["manifest"] as Dictionary).get("dependencies", []):
			var e := s.library.resolve(str(d["id"]), str(d["version"]))
			if e.is_empty():
				errs.append("[dependencia] %s necesita %s %s y no esta en la biblioteca" % [k, str(d["id"]), str(d["version"])])
				continue
			var dk := "%s@%s" % [e["id"], e["version"]]
			if not pkgs.has(dk):
				pkgs[dk] = {"id": e["id"], "version": e["version"]}
				queue.append(dk)
	return errs


## Empaqueta los paquetes pedidos ({"id@version": {id, version, hash?}}) en `files`; comprueba integridad y la huella fijada si se indica.
static func _pack_packages(s: AppStorage, pkgs: Dictionary, files: Dictionary) -> Dictionary:
	var errs: Array = []
	var pk_list: Array = []
	var keys: Array = pkgs.keys()
	keys.sort()
	for k in keys:
		var r: Dictionary = pkgs[k]
		var lp := s.library.load_package(str(r["id"]), str(r["version"]))
		if not (lp["errors"] as Array).is_empty():
			errs.append("paquete %s: %s" % [k, str(lp["errors"][0])])
			continue
		if str(lp["hash"]) != str(r.get("hash", lp["hash"])):
			errs.append("[contenido_alterado] el paquete %s no coincide con la huella fijada" % k)
			continue
		var fname := "packages/%s.zip" % k.replace("/", "__")
		files[fname] = _zip_bytes(lp["files"], s.root.path_join(".tmp"))
		pk_list.append({"id": r["id"], "version": r["version"], "hash": lp["hash"], "file": fname})
	return {"errors": errs, "list": pk_list}


## Exporta la biblioteca de paquetes (sin registros). `selection` = lista de "id@version"; vacia = todos. Cada paquete se verifica antes.
static func export_library(s: AppStorage, path: String, selection: Array = []) -> Dictionary:
	var pkgs := {}
	var errs: Array = []
	if selection.is_empty():
		for e in s.library.list():
			pkgs["%s@%s" % [e["id"], e["version"]]] = {"id": e["id"], "version": e["version"]}
	else:
		for sel in selection:
			var parts := str(sel).split("@")
			if parts.size() != 2 or not s.library.has(parts[0], parts[1]):
				errs.append("[no_encontrado] %s" % str(sel))
				continue
			pkgs[str(sel)] = {"id": parts[0], "version": parts[1]}
	if not errs.is_empty():
		return {"ok": false, "errors": errs, "packages": 0, "records": 0}
	if pkgs.is_empty():
		return {"ok": false, "errors": ["[vacio] la biblioteca no tiene paquetes que exportar"], "packages": 0, "records": 0}
	var files := {}
	var derr := _close_dependencies(s, pkgs)
	if not derr.is_empty():
		return {"ok": false, "errors": derr, "packages": 0, "records": 0}
	var pk := _pack_packages(s, pkgs, files)
	if not (pk["errors"] as Array).is_empty():
		return {"ok": false, "errors": pk["errors"], "packages": 0, "records": 0}
	return _write_bundle(s, path, [], pk["list"], files)


static func _write_bundle(s: AppStorage, path: String, entries: Array, pk_list: Array, files: Dictionary) -> Dictionary:
	var hashes := {}
	for n in files:
		hashes[n] = _sha(files[n])
	var manifest := {"schema": SCHEMA, "engine_version": CombatEngine.ENGINE_VERSION, "items": entries, "packages": pk_list, "hashes": hashes}
	var z := ZIPPacker.new()
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	if z.open(path) != OK:
		return {"ok": false, "errors": ["no se pudo crear '%s'" % path], "packages": 0, "records": 0}
	z.start_file("bundle.json")
	z.write_file(JSON.stringify(manifest, "  ", true, true).to_utf8_buffer())
	z.close_file()
	var names: Array = files.keys()
	names.sort()
	for n in names:
		z.start_file(str(n))
		z.write_file(files[n])
		z.close_file()
	z.close()
	s.log_event("export", path.get_file(), "%d paquetes, %d registros" % [pk_list.size(), entries.size()])
	return {"ok": true, "errors": [], "packages": pk_list.size(), "records": entries.size()}


## Importa un bundle. {"ok", "errors", "warnings", "records": [{store, old_id, new_id}], "packages": [id@version]}.
static func import_bundle(s: AppStorage, path: String) -> Dictionary:
	var rd := PackageSource._read_zip(path)
	if not (rd["errors"] as Array).is_empty():
		return {"ok": false, "errors": rd["errors"], "warnings": [], "records": [], "packages": []}
	var files: Dictionary = rd["files"]
	if not files.has("bundle.json"):
		return {"ok": false, "errors": ["[bundle] falta bundle.json"], "warnings": [], "records": [], "packages": []}
	var man: Variant = JSON.parse_string((files["bundle.json"] as PackedByteArray).get_string_from_utf8())
	var mig: Dictionary = SchemaMigrator.default().migrate(man) if man is Dictionary else {"ok": true, "data": man}
	if not bool(mig["ok"]):
		return {"ok": false, "errors": mig["errors"], "warnings": [], "records": [], "packages": []}
	man = mig["data"]
	if not (man is Dictionary) or str(man.get("schema", "")) != SCHEMA:
		return {"ok": false, "errors": ["[bundle] schema invalido (se esperaba %s)" % SCHEMA], "warnings": [], "records": [], "packages": []}
	var errs: Array = []
	var warns: Array = []
	if str(man.get("engine_version", "")) != CombatEngine.ENGINE_VERSION:
		warns.append("el bundle se creo con el motor %s (actual %s): no se garantiza el mismo resultado" % [str(man.get("engine_version", "?")), CombatEngine.ENGINE_VERSION])
	for n in man.get("hashes", {}):
		if not files.has(n):
			errs.append("[bundle] falta el archivo '%s'" % str(n))
		elif _sha(files[n]) != str(man["hashes"][n]):
			errs.append("[integridad] '%s': la huella no coincide (bundle alterado)" % str(n))
	for n in files:
		if str(n) != "bundle.json" and not (man.get("hashes", {}) as Dictionary).has(n):
			errs.append("[bundle] archivo no declarado '%s'" % str(n))
	if not errs.is_empty():
		return {"ok": false, "errors": errs, "warnings": warns, "records": [], "packages": []}
	# 1. paquetes (validados; conflicto de version = error explicito)
	var imported_pk: Array = []
	var pending: Array = (man.get("packages", []) as Array).duplicate()
	# Los paquetes pueden depender unos de otros: se reintenta mientras haya avance (sin necesitar un orden declarado).
	var last_errs: Array = []
	while not pending.is_empty():
		var progressed := false
		var still: Array = []
		last_errs = []
		for p in pending:
			var perr := _import_one_package(s, p, files)
			if perr == "":
				imported_pk.append("%s@%s" % [str(p["id"]), str(p["version"])])
				progressed = true
			else:
				still.append(p)
				last_errs.append("paquete %s@%s: %s" % [str(p["id"]), str(p["version"]), perr])
		pending = still
		if not progressed:
			break
	errs.append_array(last_errs)
	if not errs.is_empty():
		return {"ok": false, "errors": errs, "warnings": warns, "records": [], "packages": imported_pk}
	# 2. registros con ids nuevos (en orden de dependencia: combates/lotes antes que informes)
	var idmap := {}
	var out_records: Array = []
	var ordered: Array = (man["items"] as Array).duplicate()
	ordered.sort_custom(func(a, b): return (1 if str(a["store"]) == "reports" else 0) < (1 if str(b["store"]) == "reports" else 0))
	for it in ordered:
		var st := _store(s, str(it["store"]))
		if st == null:
			errs.append("almacen desconocido '%s'" % str(it["store"]))
			continue
		var e: Dictionary = it["entry"]
		var recfiles := {}
		for n in e["files"]:
			recfiles[n] = files["records/%s/%s/%s" % [it["store"], it["id"], n]]
		var refs: Array = []
		for r in e["refs"]:
			var c: Dictionary = (r as Dictionary).duplicate()
			if idmap.has("%s|%s" % [c.get("kind", ""), c.get("id", "")]):
				c["id"] = idmap["%s|%s" % [c.get("kind", ""), c.get("id", "")]]
			refs.append(c)
		var meta: Dictionary = (e["meta"] as Dictionary).duplicate(true)
		meta["imported_from"] = str(it["id"])
		var a := st.add(str(e["title"]), recfiles, refs, meta, str(e["kind"]))
		if not bool(a["ok"]):
			errs.append(str(a["error"]))
			continue
		var kref: String = {"battles": "battle", "batches": "batch", "reports": "report"}[str(it["store"])]
		idmap["%s|%s" % [kref, it["id"]]] = a["id"]
		out_records.append({"store": it["store"], "old_id": it["id"], "new_id": a["id"]})
	if errs.is_empty():
		s.log_event("bundle_import", path.get_file(), "%d paquetes, %d registros" % [imported_pk.size(), out_records.size()])
	return {"ok": errs.is_empty(), "errors": errs, "warnings": warns, "records": out_records, "packages": imported_pk}


## Importa un paquete del bundle. Devuelve "" si va bien o el motivo (se reintenta si depende de otro aun no importado).
static func _import_one_package(s: AppStorage, p: Dictionary, files: Dictionary) -> String:
	var tmp := s.root.path_join(".tmp")
	DirAccess.make_dir_recursive_absolute(tmp)
	var tp := tmp.path_join("_in_%d.zip" % Time.get_ticks_usec())
	var f := FileAccess.open(tp, FileAccess.WRITE)
	f.store_buffer(files[str(p["file"])])
	f.close()
	var rep := PackageImporter.new(s.library).import_package(tp)
	DirAccess.remove_absolute(tp)
	if not rep.ok():
		return "; ".join(rep.errors)
	if rep.hash != str(p["hash"]):
		return "[integridad] la huella importada no coincide con la del bundle"
	return ""
