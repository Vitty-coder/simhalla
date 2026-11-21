class_name SchemaMigrator
extends RefCounted
## Migraciones de esquema (PROJECT.md §21: versionado de formatos). Los datos declaran `"schema": "simhalla.<familia>/<N>"`.
##
## - Version == actual: sin cambios. Version MENOR: se aplican, en cadena, los pasos registrados (N -> N+1) sobre una COPIA en memoria;
##   falta de un paso = `[migracion_ausente]`. Version MAYOR que la actual: `[schema_futuro]` (la app no puede interpretar datos de una
##   version mas nueva; nunca se degrada en silencio). Familia desconocida o dato sin `schema`: no se toca.
## - La migracion es SOLO en memoria: los archivos y sus huellas (paquetes, registros) no se reescriben, de modo que la integridad y la
##   reproducibilidad de combates guardados no cambian. Cada paso debe ser una funcion pura `(Dictionary) -> Dictionary`.
## - Hoy todas las familias estan en la version 1: no hay pasos registrados (el mecanismo esta probado con pasos de prueba).

const PREFIX := "simhalla."
const KNOWN := ["manifest", "character", "abilities", "resources", "ai", "artifact", "effects", "summons", "batch", "report", "balance",
	"settings", "history", "records", "battle", "bundle", "platform_check"]

var current: Dictionary = {} ## familia -> version actual (int)
var steps: Dictionary = {} ## familia -> {desde(int): Callable}

static var _default: SchemaMigrator = null


func _init() -> void:
	for f in KNOWN:
		current[f] = 1


## Instancia compartida que usan los lectores de la aplicacion.
static func default() -> SchemaMigrator:
	if _default == null:
		_default = SchemaMigrator.new()
	return _default


## "simhalla.x/2" -> {"ok": true, "family": "x", "version": 2}.
static func parse_id(s: Variant) -> Dictionary:
	if not (s is String) or not (s as String).begins_with(PREFIX):
		return {"ok": false}
	var rest := (s as String).substr(PREFIX.length())
	var parts := rest.split("/")
	if parts.size() != 2 or parts[0] == "" or not parts[1].is_valid_int() or int(parts[1]) < 1:
		return {"ok": false}
	return {"ok": true, "family": parts[0], "version": int(parts[1])}


func register(family: String, from_version: int, fn: Callable) -> void:
	if not steps.has(family):
		steps[family] = {}
	steps[family][from_version] = fn


func set_current(family: String, version: int) -> void:
	current[family] = version


## {"ok", "data", "from", "to", "migrated", "errors": []}. `data` es una copia migrada (o el original si no hace falta migrar).
func migrate(data: Dictionary) -> Dictionary:
	var out := {"ok": true, "data": data, "from": 0, "to": 0, "migrated": false, "errors": []}
	var p := SchemaMigrator.parse_id(data.get("schema", null))
	if not bool(p["ok"]) or not current.has(p["family"]):
		return out
	var fam: String = p["family"]
	var v: int = p["version"]
	var cur: int = current[fam]
	out["from"] = v
	out["to"] = v
	if v == cur:
		return out
	if v > cur:
		out["ok"] = false
		out["errors"].append("[schema_futuro] %s/%d es mas nuevo que el soportado (%s/%d): actualice la aplicacion" % [fam, v, fam, cur])
		return out
	var d: Dictionary = data.duplicate(true)
	while v < cur:
		var fn: Variant = (steps.get(fam, {}) as Dictionary).get(v, null)
		if not (fn is Callable) or not (fn as Callable).is_valid():
			out["ok"] = false
			out["errors"].append("[migracion_ausente] no hay migracion de %s/%d a %s/%d" % [fam, v, fam, v + 1])
			return out
		var res: Variant = (fn as Callable).call(d.duplicate(true))
		if not (res is Dictionary):
			out["ok"] = false
			out["errors"].append("[migracion_fallida] la migracion %s/%d -> %d no devolvio un objeto" % [fam, v, v + 1])
			return out
		d = res
		v += 1
		d["schema"] = "%s%s/%d" % [PREFIX, fam, v]
	out["data"] = d
	out["to"] = v
	out["migrated"] = true
	return out


## Atajo para lectores tolerantes: devuelve el dato migrado o, si no se puede migrar, el original (el lector lo rechazara o ignorara).
func upgraded(data: Variant) -> Variant:
	if not (data is Dictionary):
		return data
	var r := migrate(data)
	return r["data"] if bool(r["ok"]) else data
