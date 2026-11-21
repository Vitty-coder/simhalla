class_name ApplyStatusOperation
extends EffectOperation
## {"type":"apply_status","status":"poison","stacks":1,"duration":3 | {unit,amount,...},
##  "magnitude":"caster.MAG * 0.1","chance":0.3,"on":"targets|caster"}
## `duration` y `magnitude` son opcionales (por defecto los del estado).

func type_id() -> String:
	return "apply_status"


func allowed_keys() -> Array:
	return ["type", "status", "stacks", "duration", "magnitude"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if str(effect.get("status", "")) == "":
		errs.append("apply_status: falta 'status'")
	if effect.has("stacks") and (not (effect["stacks"] is float or effect["stacks"] is int) or int(effect["stacks"]) < 1):
		errs.append("apply_status.stacks debe ser un entero >= 1")
	if effect.has("duration"):
		errs.append_array(Duration.validate(effect["duration"], "apply_status.duration"))
	if effect.has("magnitude"):
		if effect["magnitude"] is float or effect["magnitude"] is int:
			pass
		else:
			errs.append_array(validate_formula(effect["magnitude"], "apply_status.magnitude"))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	for target in ctx.targets:
		if eng.is_aborted():
			return
		var mag := 1.0
		if effect.has("magnitude"):
			if effect["magnitude"] is String:
				var r := eng.eval_formula(str(effect["magnitude"]), FormulaContext.new(ctx.actor, target, ctx.status))
				if not r["ok"]:
					eng.abort("formula_error", "apply_status.magnitude: %s" % r["error"])
					return
				mag = float(r["value"])
			else:
				mag = float(effect["magnitude"])
		var opts := {"stacks": int(effect.get("stacks", 1)), "magnitude": mag, "cause": ctx.cause_id}
		if effect.has("duration"):
			opts["duration"] = effect["duration"]
		eng.status_service.apply(str(effect["status"]), target, ctx.actor, opts)
