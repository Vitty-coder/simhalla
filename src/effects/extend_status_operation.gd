class_name ExtendStatusOperation
extends EffectOperation
## Alarga o acorta la duracion restante: {"type":"extend_status","status":"id","amount":2}
## (negativo acorta; en la unidad de la duracion del estado; <= 0 restante lo expira).

func type_id() -> String:
	return "extend_status"


func allowed_keys() -> Array:
	return ["type", "status", "tags", "amount"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if not (effect.has("status") or effect.has("tags")):
		errs.append("extend_status: indique 'status' o 'tags'")
	if not (effect.get("amount", null) is float or effect.get("amount", null) is int) or float(effect.get("amount", 0)) == 0.0:
		errs.append("extend_status.amount debe ser un numero distinto de 0")
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	for target in ctx.targets:
		for st in ctx.engine.status_service.matching(target, effect):
			ctx.engine.status_service.adjust_duration(st, float(effect["amount"]))
