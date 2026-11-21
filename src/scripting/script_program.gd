class_name ScriptProgram
extends RefCounted
## Programa compilado (AST inmutable) de un script. Solo datos: no ejecuta nada.

var name: String = ""
var source_hash: String = ""
var source_size: int = 0
var consts: Dictionary = {} ## nombre -> valor literal
var functions: Dictionary = {} ## nombre -> {"params": Array, "body": Array, "line": int, "calls": Array (API), "user_calls": Array}
## Analisis estatico para valoracion/depuracion (fase 6): contratos verificables, nada de precios.
var analysis: Dictionary = {}

const ENTRY := {"effect": "run", "ai": "decide"}


## Errores de enlace para un contexto ("effect" | "ai"): punto de entrada y llamadas
## alcanzables desde el, todas permitidas en ese contexto.
func check_context(context: String) -> Array:
	var errs: Array = []
	var entry: String = ENTRY.get(context, "")
	if entry == "":
		return ["contexto de script desconocido '%s'" % context]
	if not functions.has(entry):
		return ["script '%s': falta la funcion de entrada `fn %s(...)` para el contexto '%s'" % [name, entry, context]]
	if (functions[entry]["params"] as Array).size() != 1:
		errs.append("script '%s': `%s` debe tener exactamente 1 parametro" % [name, entry])
	var seen := {}
	var stack: Array = [entry]
	while not stack.is_empty():
		var fname: String = stack.pop_back()
		if seen.has(fname):
			continue
		seen[fname] = true
		for c in functions[fname]["calls"]:
			if not ScriptApi.allowed_in(str(c), context):
				errs.append("script '%s': `%s()` no esta permitida en el contexto '%s' (API v%d)" % [name, str(c), context, ScriptApi.VERSION])
		for u in functions[fname]["user_calls"]:
			stack.append(str(u))
	return errs


## Contrato mecanico verificable de un efecto script: {max_damage?, max_heal?}. Cada llamada con poder
## mecanico alcanzable debe estar cubierta (deal_damage <- max_damage, heal <- max_heal); apply_status,
## remove_status y modify_resource no se pueden cubrir. El motor hace cumplir los topes en ejecucion.
const POWER_COVER := {"deal_damage": "max_damage", "heal": "max_heal"}
const UNCOVERABLE := ["apply_status", "remove_status", "modify_resource"]


func check_contract(contract: Dictionary) -> Array:
	var errs: Array = []
	for c in reachable_calls("effect"):
		if UNCOVERABLE.has(c):
			errs.append("script '%s': el contrato no puede cubrir `%s()`" % [name, c])
		elif POWER_COVER.has(c) and not contract.has(POWER_COVER[c]):
			errs.append("script '%s': usa `%s()` pero el contrato no declara `%s`" % [name, c, POWER_COVER[c]])
	return errs


## Llamadas de API alcanzables desde un contexto (para valoracion).
func reachable_calls(context: String) -> Array:
	var out := {}
	var entry: String = ENTRY.get(context, "")
	if not functions.has(entry):
		return []
	var seen := {}
	var stack: Array = [entry]
	while not stack.is_empty():
		var fname: String = stack.pop_back()
		if seen.has(fname):
			continue
		seen[fname] = true
		for c in functions[fname]["calls"]:
			out[str(c)] = true
		for u in functions[fname]["user_calls"]:
			stack.append(str(u))
	var l: Array = out.keys()
	l.sort()
	return l
