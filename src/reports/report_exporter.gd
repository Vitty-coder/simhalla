class_name ReportExporter
extends RefCounted
## Exportadores de informes: JSON, Markdown y HTML a partir del MISMO modelo versionado (`simhalla.report/1`).
## El JSON es el propio modelo (claves ordenadas, sin marcas de tiempo): un informe es reproducible byte a byte.
## `content_hash` = SHA-256 del JSON del modelo SIN `measurement` (rendimiento medido, no reproducible).
## No se exige CSV ni PDF (PROJECT.md §14.2).

## Modelo sin `measurement`, con enteros normalizados (JSON los devuelve como float) y decimales a 1e-9: una ida y vuelta
## por JSON no cambia la huella (el JSON exportado conserva la precision completa). (Las semillas de 64 bits van como TEXTO en el modelo: un JSON numerico perderia precision.)
static func canonical(model: Dictionary) -> Dictionary:
	var m: Dictionary = _norm(model)
	m.erase("measurement")
	return m


static func _norm(v: Variant) -> Variant:
	if v is float:
		# El analizador JSON de Godot no redondea bien el ultimo bit: la huella usa los decimales como TEXTO (9) y los enteros como enteros.
		if absf(v - roundf(v)) < 1.0e-9 and absf(v) < 1.0e15: # 0.9999999999999999 y 1.0 son el mismo entero
			return int(roundf(v))
		return "%.9f" % v
	if v is Array:
		return (v as Array).map(func(x): return _norm(x))
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _norm(v[k])
		return d
	return v


static func to_json(model: Dictionary, indent: String = "  ") -> String:
	return JSON.stringify(model, indent, true, true) + "\n"


static func content_hash(model: Dictionary) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(JSON.stringify(canonical(model), "", true, true).to_utf8_buffer())
	return h.finish().hex_encode()


## `with_measurement`: incluye el rendimiento medido (NO reproducible); por defecto se omite para que MD/HTML sean reproducibles.
static func to_markdown(model: Dictionary, with_measurement: bool = false) -> String:
	return MarkdownRenderer.render(ReportDocument.from_model(model, with_measurement), content_hash(model))


static func to_html(model: Dictionary, with_measurement: bool = false) -> String:
	return HtmlRenderer.render(ReportDocument.from_model(model, with_measurement), content_hash(model))


## Escribe `<base>.json`, `<base>.md` y `<base>.html` en `dir`. {"paths": [...], "errors": [...]}.
static func write_all(model: Dictionary, dir: String, base: String) -> Dictionary:
	var errs: Array = []
	var paths: Array = []
	if not RegEx.create_from_string("^[A-Za-z0-9_.-]{1,80}$").search(base):
		return {"paths": [], "errors": ["nombre de archivo no valido '%s'" % base]}
	DirAccess.make_dir_recursive_absolute(dir)
	for pair in [["json", to_json(model)], ["md", to_markdown(model)], ["html", to_html(model)]]:
		var p: String = dir.path_join("%s.%s" % [base, pair[0]])
		var f := FileAccess.open(p, FileAccess.WRITE)
		if f == null:
			errs.append("no se pudo escribir '%s'" % p)
			continue
		f.store_string(pair[1])
		f.close()
		paths.append(p)
	return {"paths": paths, "errors": errs}
