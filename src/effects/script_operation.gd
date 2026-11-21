class_name ScriptOperation
extends EffectOperation
## Operacion `script`: mecanica extraordinaria en SimScript (ver docs/SCRIPTING_API.md).
## {"type":"script","script":"mi_script","args":{"potencia":3}}
## Ejecuta `fn run(ctx)` del script una vez por accion; ctx = {caster, targets, ability, args, turn}.
## `contract` (opcional): {"max_damage": N, "max_heal": M} = topes por ejecucion que el MOTOR hace cumplir
## (error de script si se superan); permite valorar el script en la fase 6 (SCRIPTING_API.md §6).
## El script solo puede usar la API permitida; sus cambios pasan por el motor (eventos, interceptores).

func type_id() -> String:
	return "script"


func allowed_keys() -> Array:
	return ["type", "script", "args", "contract"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if not (effect.get("script", null) is String) or not RegEx.create_from_string("^[a-z][a-z0-9_]{0,63}$").search(str(effect.get("script", ""))):
		errs.append("script.script debe ser un identificador en minusculas (nombre del archivo sin .sim)")
	if effect.has("args"):
		if not (effect["args"] is Dictionary):
			errs.append("script.args debe ser un objeto")
		else:
			var bad := ScriptValue.check_plain(effect["args"])
			if bad != "":
				errs.append("script.args: %s" % bad)
	if effect.has("contract"):
		var c: Variant = effect["contract"]
		if not (c is Dictionary) or (c as Dictionary).is_empty():
			errs.append("script.contract debe ser un objeto {max_damage?, max_heal?}")
		else:
			for k in c:
				if not ["max_damage", "max_heal"].has(str(k)):
					errs.append("script.contract: propiedad desconocida '%s' (use max_damage, max_heal)" % str(k))
				elif not (c[k] is float or c[k] is int) or float(c[k]) < 0.0 or float(c[k]) > 10000000.0:
					errs.append("script.contract.%s debe ser un numero entre 0 y 10000000" % str(k))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	ScriptRunner.run_effect(ctx, str(effect["script"]), effect.get("args", {}), effect.get("contract", null))
