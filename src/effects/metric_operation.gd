class_name MetricOperation
extends EffectOperation
## Metrica personalizada: {"type":"metric","name":"fury_spent","amount":"caster.res.fury"}
## Acumula `amount` (por objetivo) bajo `name`, total y por entidad que la genera;
## aparece en CombatResult.metrics. No altera el combate.

func type_id() -> String:
	return "metric"


func allowed_keys() -> Array:
	return ["type", "name", "amount"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if not (effect.get("name", null) is String) or not RegEx.create_from_string("^[a-z][a-z0-9_]{0,31}$").search(str(effect.get("name", ""))):
		errs.append("metric.name debe ser un identificador en minusculas")
	if effect.get("amount", null) is float or effect.get("amount", null) is int:
		return errs
	errs.append_array(validate_formula(effect.get("amount", null), "metric.amount"))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	for t in ctx.targets:
		var amount: float
		if effect["amount"] is String:
			var r := eng.eval_formula(str(effect["amount"]), FormulaContext.new(ctx.actor, t, ctx.status))
			if not r["ok"]:
				eng.abort("formula_error", "metric.amount: %s" % r["error"])
				return
			amount = float(r["value"])
		else:
			amount = float(effect["amount"])
		eng.add_metric(str(effect["name"]), ctx.actor.id, amount)
