class_name EffectOperation
extends RefCounted
## Contrato de una operacion declarativa de efecto (damage, heal, ...).
##
## Las operaciones NUNCA tocan el estado directamente: pasan por el motor
## (CombatEngine.change_hp, emit, ...) para que todo cambio sea validado,
## interceptable y trazable. Nuevas operaciones se registran en
## OperationRegistry sin modificar el motor.

var registry: OperationRegistry = null ## asignado por OperationRegistry.register (operaciones anidadas)


func type_id() -> String:
	return ""


## Claves permitidas del diccionario de efecto (cualquier otra se rechaza).
func allowed_keys() -> Array:
	return ["type"]


## Comprueba claves desconocidas y tipos simples; devuelve errores.
static func check_keys(d: Dictionary, allowed: Array, label: String) -> Array:
	var errs: Array = []
	for k in d:
		if not allowed.has(str(k)):
			errs.append("%s: propiedad desconocida '%s' (permitidas: %s)" % [label, str(k), ", ".join(allowed)])
	return errs


static func check_types(d: Dictionary, bools: Array, numbers: Array, label: String) -> Array:
	var errs: Array = []
	for k in bools:
		if d.has(k) and not (d[k] is bool):
			errs.append("%s.%s debe ser booleano" % [label, k])
	for k in numbers:
		if d.has(k) and not (d[k] is float or d[k] is int):
			errs.append("%s.%s debe ser numerico" % [label, k])
	return errs


## Devuelve la lista de errores de validacion del diccionario de efecto.
func validate(_effect: Dictionary) -> Array:
	return []


func resolve(_ctx: ActionContext, _effect: Dictionary) -> void:
	pass


## Validacion comun de una formula textual (sintaxis y origenes permitidos).
static func validate_formula(text: Variant, label: String) -> Array:
	var errs: Array = []
	if not (text is String):
		errs.append("%s: la formula debe ser texto" % label)
		return errs
	var f := Formula.parse(text)
	if not f.is_valid():
		errs.append("%s: %s" % [label, f.error])
		return errs
	for p in f.referenced_paths():
		var head: String = str(p).split(".")[0]
		if head != "caster" and head != "target" and head != "status":
			errs.append("%s: origen de variable no permitido '%s'" % [label, p])
	return errs
