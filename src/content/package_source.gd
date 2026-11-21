class_name PackageSource
extends RefCounted
## Lectura SEGURA de un paquete (carpeta o ZIP) a memoria.
##
## Defensas: rutas relativas peligrosas (.., absolutas, "\\", ":", NUL, segmentos
## vacios), colisiones por mayusculas/minusculas, enlaces simbolicos, numero de
## archivos, tamano por archivo y total, y bombas de compresion (los tamanos
## descomprimidos se leen del directorio central del ZIP ANTES de extraer).
## Nunca ejecuta ni interpreta el contenido: solo devuelve bytes.

const MAX_FILES := 256
const MAX_FILE_BYTES := 2 * 1024 * 1024
const MAX_TOTAL_BYTES := 16 * 1024 * 1024
const MAX_ZIP_BYTES := 16 * 1024 * 1024
const MAX_RATIO := 200 ## descomprimido / comprimido (archivos > 64 KiB)


## Devuelve {"files": {ruta_relativa: PackedByteArray}, "errors": Array[String]}.
static func read(path: String) -> Dictionary:
	if DirAccess.dir_exists_absolute(path):
		return _read_dir(path)
	if FileAccess.file_exists(path):
		var lower := path.to_lower()
		if lower.ends_with(".zip") or lower.ends_with(".simpkg"):
			return _read_zip(path)
		return {"files": {}, "errors": ["[formato] '%s' no es una carpeta ni un .zip/.simpkg" % path]}
	return {"files": {}, "errors": ["[no_encontrado] no existe '%s'" % path]}


## "" si la ruta relativa es segura; si no, el motivo.
static func check_rel_path(p: String) -> String:
	if p == "":
		return "ruta vacia"
	if p.contains("\\"):
		return "contiene '\\'"
	if p.contains(":"):
		return "contiene ':'"
	if p.to_utf8_buffer().has(0):
		return "contiene NUL"
	if p.begins_with("/"):
		return "ruta absoluta"
	for seg in p.split("/"):
		if seg == "" or seg == "." or seg == "..":
			return "segmento no permitido '%s'" % seg
	if p.length() > 200:
		return "ruta demasiado larga"
	return ""


static func _read_dir(root: String) -> Dictionary:
	var files := {}
	var errors: Array[String] = []
	var stack: Array = [""]
	var total := 0
	while not stack.is_empty():
		var rel_dir: String = stack.pop_back()
		var abs_dir := root if rel_dir == "" else root.path_join(rel_dir)
		var d := DirAccess.open(abs_dir)
		if d == null:
			errors.append("[lectura] no se puede abrir la carpeta '%s'" % abs_dir)
			continue
		for sub in d.get_directories():
			var rel := sub if rel_dir == "" else rel_dir + "/" + sub
			if d.is_link(sub):
				errors.append("[enlace_simbolico] '%s' es un enlace simbolico" % rel)
			else:
				stack.append(rel)
		for f in d.get_files():
			var rel := f if rel_dir == "" else rel_dir + "/" + f
			if d.is_link(f):
				errors.append("[enlace_simbolico] '%s' es un enlace simbolico" % rel)
				continue
			var bad := check_rel_path(rel)
			if bad != "":
				errors.append("[path_traversal] '%s': %s" % [rel, bad])
				continue
			if files.size() >= MAX_FILES:
				errors.append("[limite] mas de %d archivos" % MAX_FILES)
				return {"files": files, "errors": errors}
			var fa := FileAccess.open(root.path_join(rel), FileAccess.READ)
			if fa == null:
				errors.append("[lectura] no se puede leer '%s'" % rel)
				continue
			if fa.get_length() > MAX_FILE_BYTES:
				errors.append("[limite] '%s' supera %d bytes" % [rel, MAX_FILE_BYTES])
				continue
			var bytes := fa.get_buffer(fa.get_length())
			total += bytes.size()
			if total > MAX_TOTAL_BYTES:
				errors.append("[limite] el paquete supera %d bytes en total" % MAX_TOTAL_BYTES)
				return {"files": files, "errors": errors}
			files[rel] = bytes
	return {"files": files, "errors": errors}


static func _u16(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8)


static func _u32(b: PackedByteArray, o: int) -> int:
	return b[o] | (b[o + 1] << 8) | (b[o + 2] << 16) | (b[o + 3] << 24)


## Entradas del directorio central: [{name, csize, usize}] o error.
static func zip_entries(raw: PackedByteArray) -> Dictionary:
	var n := raw.size()
	var eocd := -1
	var i := n - 22
	var lowest := maxi(0, n - 22 - 65535)
	while i >= lowest:
		if raw[i] == 0x50 and raw[i + 1] == 0x4b and raw[i + 2] == 0x05 and raw[i + 3] == 0x06:
			eocd = i
			break
		i -= 1
	if eocd < 0:
		return {"error": "ZIP invalido (sin directorio central)"}
	var count := _u16(raw, eocd + 10)
	var off := _u32(raw, eocd + 16)
	if count > MAX_FILES * 2:
		return {"error": "demasiadas entradas en el ZIP (%d)" % count}
	var entries: Array = []
	for k in count:
		if off + 46 > n or _u32(raw, off) != 0x02014b50:
			return {"error": "directorio central del ZIP corrupto"}
		var csize := _u32(raw, off + 20)
		var usize := _u32(raw, off + 24)
		var nlen := _u16(raw, off + 28)
		var elen := _u16(raw, off + 30)
		var clen := _u16(raw, off + 32)
		if off + 46 + nlen > n:
			return {"error": "directorio central del ZIP corrupto"}
		var name := raw.slice(off + 46, off + 46 + nlen).get_string_from_utf8()
		entries.append({"name": name, "csize": csize, "usize": usize})
		off += 46 + nlen + elen + clen
	return {"entries": entries}


static func _read_zip(path: String) -> Dictionary:
	var files := {}
	var errors: Array[String] = []
	var fa := FileAccess.open(path, FileAccess.READ)
	if fa == null:
		return {"files": files, "errors": ["[lectura] no se puede abrir '%s'" % path]}
	if fa.get_length() > MAX_ZIP_BYTES:
		return {"files": files, "errors": ["[limite] el ZIP supera %d bytes" % MAX_ZIP_BYTES]}
	var raw := fa.get_buffer(fa.get_length())
	var idx := zip_entries(raw)
	if idx.has("error"):
		return {"files": files, "errors": ["[formato] " + str(idx["error"])]}
	var reader := ZIPReader.new()
	if reader.open(path) != OK:
		return {"files": files, "errors": ["[formato] no se puede abrir el ZIP"]}
	var total := 0
	var seen_lower := {}
	for e in idx["entries"]:
		var name: String = e["name"]
		if name.ends_with("/"):
			continue
		var bad := check_rel_path(name)
		if bad != "":
			errors.append("[path_traversal] '%s': %s" % [name, bad])
			continue
		if seen_lower.has(name.to_lower()):
			errors.append("[colision] '%s' colisiona con '%s' (mayusculas/minusculas o duplicado)" % [name, seen_lower[name.to_lower()]])
			continue
		seen_lower[name.to_lower()] = name
		if files.size() >= MAX_FILES:
			errors.append("[limite] mas de %d archivos" % MAX_FILES)
			break
		var usize: int = e["usize"]
		var csize: int = maxi(e["csize"], 1)
		if usize > MAX_FILE_BYTES:
			errors.append("[limite] '%s' descomprimido (%d bytes) supera %d" % [name, usize, MAX_FILE_BYTES])
			continue
		if usize > 65536 and usize / csize > MAX_RATIO:
			errors.append("[bomba_compresion] '%s': ratio %d:1 sospechoso" % [name, usize / csize])
			continue
		total += usize
		if total > MAX_TOTAL_BYTES:
			errors.append("[limite] el paquete descomprimido supera %d bytes" % MAX_TOTAL_BYTES)
			break
		var bytes := reader.read_file(name)
		if bytes.size() != usize:
			errors.append("[formato] '%s': tamano real (%d) distinto del declarado (%d)" % [name, bytes.size(), usize])
			continue
		files[name] = bytes
	reader.close()
	return {"files": files, "errors": errors}


## Huella estable del contenido (independiente de carpeta/ZIP y del orden):
## SHA-256 de lineas "ruta\0sha256(archivo)\n" en orden alfabetico.
static func content_hash(files: Dictionary) -> String:
	var names: Array = files.keys()
	names.sort()
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	for n in names:
		var h := HashingContext.new()
		h.start(HashingContext.HASH_SHA256)
		h.update(files[n])
		ctx.update((str(n) + "\t" + h.finish().hex_encode() + "\n").to_utf8_buffer())
	return ctx.finish().hex_encode()


const SCRIPT_RE := "^scripts/[a-z][a-z0-9_]{0,63}\\.sim$"


## Extrae los scripts de un conjunto de archivos: {id: texto}. Los que no sean UTF-8 valido se omiten
## (el importador ya los habra rechazado). Solo lee; nunca ejecuta.
static func scripts_of(files: Dictionary) -> Dictionary:
	var out := {}
	var rx := RegEx.create_from_string(SCRIPT_RE)
	for rel in files:
		if rx.search(str(rel)) != null:
			var bytes: PackedByteArray = files[rel]
			var text := bytes.get_string_from_utf8()
			if text.to_utf8_buffer() == bytes:
				out[str(rel).get_file().get_basename()] = text
	return out
