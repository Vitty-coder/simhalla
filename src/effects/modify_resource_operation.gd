class_name ModifyResourceOperation
extends EffectOperation
## {"type":"modify_resource","resource":"mana","amount":"caster.MAG * 0.2","mode":"add|set","property":"value|max"}
## Cambia el valor (add/set) o el maximo de un recurso. Los limites emiten resource_limit.

func type_id() -> String:
	return "modify_resource"


func allowed_keys() -> Array:
	return ["type", "resource", "amount", "mode", "property"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if str(effect.get("resource", "")) == "":
		errs.append("modify_resource: falta 'resource'")
	if not ["add", "set"].has(str(effect.get("mode", "add"))):
		errs.append("modify_resource.mode debe ser add o set")
	if not ["value", "max"].has(str(effect.get("property", "value"))):
		errs.append("modify_resource.property debe ser value o max")
	if effect.get("amount", null) is float or effect.get("amount", null) is int:
		return errs
	errs.append_array(validate_formula(effect.get("amount", null), "modify_resource.amount"))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	for target in ctx.targets:
		if eng.is_aborted():
			return
		var r: ResourceState = target.get_resource(str(effect["resource"]))
		if r == null or not target.alive:
			eng.emit(EventTypes.TARGET_SKIPPED, ctx.actor.id, target.id, {"reason": "sin_recurso:" + str(effect["resource"])}, ctx.cause_id)
			continue
		var amount: float
		if effect["amount"] is String:
			var res := eng.eval_formula(str(effect["amount"]), FormulaContext.new(ctx.actor, target, ctx.status))
			if not res["ok"]:
				eng.abort("formula_error", "modify_resource.amount: %s" % res["error"])
				return
			amount = float(res["value"])
		else:
			amount = float(effect["amount"])
		var mode := str(effect.get("mode", "add"))
		if str(effect.get("property", "value")) == "max":
			eng.change_resource_max(target, r.id, amount if mode == "set" else r.max_value + amount, ctx.cause_id)
		else:
			eng.change_resource(target, r.id, (amount - r.value) if mode == "set" else amount, "effect", ctx.cause_id)
