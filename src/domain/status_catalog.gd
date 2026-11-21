class_name StatusCatalog
extends RefCounted
## Catalogo de definiciones de estados de un combate: nativos (datos) +
## personalizados aportados por las entidades. Ids unicos.

const NATIVE_PATH := "res://content/statuses/native_statuses.json"

var native_ids: Array = [] ## ids cargados de los estados nativos (datos ilustrativos; no se validan contra el catalogo elemental)
var _defs: Dictionary = {}
var _raw: Dictionary = {} ## id -> definicion original (para admitir duplicados identicos)


func register(def: StatusDef) -> String:
	if _defs.has(def.id):
		return "estado duplicado '%s'" % def.id
	_defs[def.id] = def
	return ""


func has(id: String) -> bool:
	return _defs.has(id)


func get_def(id: String) -> StatusDef:
	return _defs.get(id, null)


func ids() -> Array:
	var out: Array = _defs.keys()
	out.sort()
	return out


## Carga los estados nativos (datos). Devuelve errores.
func load_native(registry: OperationRegistry) -> Array:
	var f := FileAccess.open(NATIVE_PATH, FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	if not (parsed is Dictionary):
		return ["no se pudo leer %s" % NATIVE_PATH]
	var errs := register_all(parsed.get("statuses", []), registry)
	native_ids = _defs.keys()
	return errs


func register_all(list: Array, registry: OperationRegistry) -> Array:
	var errs: Array = []
	for d in list:
		if not (d is Dictionary):
			errs.append("cada estado debe ser un objeto")
			continue
		var sid := str(d.get("id", ""))
		if _raw.has(sid):
			# Una definicion identica (p. ej. dos copias del mismo PJ) es valida; una distinta, no.
			if JSON.stringify(_raw[sid], "", true) != JSON.stringify(d, "", true):
				errs.append("estado '%s' redefinido con contenido distinto" % sid)
			continue
		var r := StatusDef.from_dict(d, registry)
		if r["def"] == null:
			errs.append_array(r["errors"])
			continue
		var e := register(r["def"])
		if e != "":
			errs.append(e)
		else:
			_raw[sid] = (d as Dictionary).duplicate(true)
	return errs
