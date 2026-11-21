class_name ScriptLimits
extends RefCounted
## Limites tecnicos del runtime de scripts (reglamento `scripting.*`). Cada uno tiene
## un techo duro que el reglamento no puede superar (el contenido nunca los cambia).

const CEILINGS := {
	"max_instructions": 1000000, "max_call_depth": 64, "max_collection": 4096, "max_string": 4096,
	"max_mutations": 1024, "max_source_bytes": 262144, "max_ast_nodes": 50000,
}
const DEFAULTS := {
	"max_instructions": 20000, "max_call_depth": 16, "max_collection": 256, "max_string": 256,
	"max_mutations": 32, "max_source_bytes": 16384, "max_ast_nodes": 3000,
}

var max_instructions: int = 20000 ## nodos evaluados por invocacion
var max_call_depth: int = 16
var max_collection: int = 256 ## elementos por lista/mapa creados por el script
var max_string: int = 256 ## caracteres por texto creado por el script
var max_mutations: int = 32 ## operaciones de combate que cambian el estado, por invocacion
var max_source_bytes: int = 16384
var max_ast_nodes: int = 3000


static func default_limits() -> ScriptLimits:
	return ScriptLimits.new()


static func from_ruleset(rules: Ruleset) -> ScriptLimits:
	var l := ScriptLimits.new()
	if rules == null:
		return l
	for k in DEFAULTS:
		var v: Variant = rules.get_path_value("scripting." + k)
		l.set(k, clampi(int(v) if (v is float or v is int) else int(DEFAULTS[k]), 1, int(CEILINGS[k])))
	return l


static func validate_ruleset(rules: Ruleset) -> Array:
	var errs: Array = []
	for k in DEFAULTS:
		var v: Variant = rules.get_path_value("scripting." + k)
		if not (v is float or v is int) or int(v) < 1 or int(v) > int(CEILINGS[k]):
			errs.append("scripting.%s debe ser un entero entre 1 y %d" % [k, int(CEILINGS[k])])
	return errs
