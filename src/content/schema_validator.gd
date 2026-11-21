class_name SchemaValidator
extends RefCounted
## Validador de un subconjunto de JSON Schema (draft 2020-12) para los
## esquemas publicos de `schemas/`. Pensado para dar errores claros por
## archivo y ruta de propiedad, utiles tambien a una IA externa.
##
## Palabras clave soportadas: type (string|number|integer|boolean|object|array|null,
## o lista), enum, const, required, properties, additionalProperties (false|esquema),
## items, minItems, maxItems, minimum, maximum, pattern, minLength, maxLength,
## minProperties, $ref ("#/definitions/x" o "otro.schema.json#/definitions/x").
## Cualquier otra palabra clave (title, description, $id, $schema, examples,
## definitions) se ignora. Una propiedad no declarada con additionalProperties
## false es un error ("propiedad desconocida").

const MAX_DEPTH := 32

var _dir: String
var _cache: Dictionary = {}


func _init(schemas_dir: String = "res://schemas") -> void:
	_dir = schemas_dir


func load_schema(file_name: String) -> Dictionary:
	if _cache.has(file_name):
		return _cache[file_name]
	var f := FileAccess.open(_dir.path_join(file_name), FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	_cache[file_name] = parsed if parsed is Dictionary else {}
	return _cache[file_name]


## Devuelve la lista de errores "ruta: mensaje" (vacia si es valido).
func validate(schema_file: String, data: Variant) -> Array:
	var errs: Array = []
	var root := load_schema(schema_file)
	if root.is_empty():
		return ["esquema '%s' no disponible" % schema_file]
	_check(root, schema_file, data, "", errs, 0)
	return errs


func _resolve(ref: String, cur_file: String) -> Array:
	var parts := ref.split("#")
	var file := cur_file if parts[0] == "" else parts[0]
	var node: Variant = load_schema(file)
	if parts.size() > 1 and parts[1] != "":
		for seg in parts[1].trim_prefix("/").split("/"):
			if node is Dictionary and node.has(seg):
				node = node[seg]
			else:
				return [{}, file]
	return [node if node is Dictionary else {}, file]


static func _type_ok(t: String, v: Variant) -> bool:
	match t:
		"object":
			return v is Dictionary
		"array":
			return v is Array
		"string":
			return v is String
		"boolean":
			return v is bool
		"null":
			return v == null
		"number":
			return v is float or v is int
		"integer":
			return (v is int) or (v is float and v == floorf(v) and absf(v) < 9.0e15)
	return false


static func _type_name(v: Variant) -> String:
	if v == null:
		return "null"
	if v is Dictionary:
		return "objeto"
	if v is Array:
		return "lista"
	if v is String:
		return "texto"
	if v is bool:
		return "booleano"
	if v is float or v is int:
		return "numero"
	return "desconocido"


func _check(schema: Dictionary, file: String, v: Variant, path: String, errs: Array, depth: int) -> void:
	var where := path if path != "" else "(raiz)"
	if depth > MAX_DEPTH:
		errs.append("%s: estructura demasiado anidada" % where)
		return
	if schema.has("$ref"):
		var r := _resolve(str(schema["$ref"]), file)
		_check(r[0], r[1], v, path, errs, depth + 1)
		return
	if schema.has("type"):
		var types: Array = schema["type"] if schema["type"] is Array else [schema["type"]]
		var ok := false
		for t in types:
			if _type_ok(str(t), v):
				ok = true
				break
		if not ok:
			errs.append("%s: se esperaba %s y es %s" % [where, " o ".join(types), _type_name(v)])
			return
	if schema.has("const") and v != schema["const"]:
		errs.append("%s: debe valer '%s'" % [where, str(schema["const"])])
	if schema.has("enum") and not (schema["enum"] as Array).has(v):
		errs.append("%s: valor '%s' no permitido (use: %s)" % [where, str(v), ", ".join((schema["enum"] as Array).map(func(x): return str(x)))])
	if v is String:
		if schema.has("minLength") and (v as String).length() < int(schema["minLength"]):
			errs.append("%s: demasiado corto (min %d caracteres)" % [where, int(schema["minLength"])])
		if schema.has("maxLength") and (v as String).length() > int(schema["maxLength"]):
			errs.append("%s: demasiado largo (max %d caracteres)" % [where, int(schema["maxLength"])])
		if schema.has("pattern"):
			var re := RegEx.new()
			if re.compile(str(schema["pattern"])) == OK and re.search(v) == null:
				errs.append("%s: '%s' no cumple el formato %s" % [where, v, str(schema["pattern"])])
	if v is float or v is int:
		if schema.has("minimum") and float(v) < float(schema["minimum"]):
			errs.append("%s: %s es menor que el minimo %s" % [where, str(v), str(schema["minimum"])])
		if schema.has("maximum") and float(v) > float(schema["maximum"]):
			errs.append("%s: %s es mayor que el maximo %s" % [where, str(v), str(schema["maximum"])])
	if v is Array:
		var arr: Array = v
		if schema.has("minItems") and arr.size() < int(schema["minItems"]):
			errs.append("%s: requiere al menos %d elementos" % [where, int(schema["minItems"])])
		if schema.has("maxItems") and arr.size() > int(schema["maxItems"]):
			errs.append("%s: admite como maximo %d elementos" % [where, int(schema["maxItems"])])
		if schema.has("items") and schema["items"] is Dictionary:
			for i in arr.size():
				_check(schema["items"], file, arr[i], "%s[%d]" % [path, i], errs, depth + 1)
	if v is Dictionary:
		var d: Dictionary = v
		var props: Dictionary = schema.get("properties", {})
		if schema.has("minProperties") and d.size() < int(schema["minProperties"]):
			errs.append("%s: requiere al menos %d propiedades" % [where, int(schema["minProperties"])])
		for req in schema.get("required", []):
			if not d.has(req):
				errs.append("%s: falta la propiedad obligatoria '%s'" % [where, str(req)])
		var keys: Array = d.keys()
		keys.sort()
		for k in keys:
			var sub := path + ("." if path != "" else "") + str(k)
			if props.has(k):
				_check(props[k], file, d[k], sub, errs, depth + 1)
			else:
				var ap: Variant = schema.get("additionalProperties", true)
				if ap is bool and not ap:
					var names: Array = props.keys()
					names.sort()
					errs.append("%s: propiedad desconocida '%s' (permitidas: %s)" % [where, str(k), ", ".join(names)])
				elif ap is Dictionary:
					_check(ap, file, d[k], sub, errs, depth + 1)
