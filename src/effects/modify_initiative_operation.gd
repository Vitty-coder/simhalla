class_name ModifyInitiativeOperation
extends EffectOperation
## {"type":"modify_initiative","mode":"add|set|steal|extra_turn","amount":"200"}
##   add: suma (o resta si negativo) iniciativa en unidades; set: fija; steal: el
##   lanzador roba `amount` al objetivo; extra_turn: concede un turno extra
##   (iniciativa +umbral). La iniciativa nunca baja de 0 (provisional, D-041).

func type_id() -> String:
	return "modify_initiative"


func allowed_keys() -> Array:
	return ["type", "mode", "amount"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	var mode := str(effect.get("mode", ""))
	if not ["add", "set", "steal", "extra_turn"].has(mode):
		errs.append("modify_initiative.mode debe ser add, set, steal o extra_turn")
		return errs
	if mode == "extra_turn":
		return errs
	if effect.get("amount", null) is float or effect.get("amount", null) is int:
		return errs
	errs.append_array(validate_formula(effect.get("amount", null), "modify_initiative.amount"))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	var mode := str(effect["mode"])
	for target in ctx.targets:
		if eng.is_aborted():
			return
		if not target.alive:
			continue
		var amount := 0.0
		if mode != "extra_turn":
			if effect["amount"] is String:
				var res := eng.eval_formula(str(effect["amount"]), FormulaContext.new(ctx.actor, target, ctx.status))
				if not res["ok"]:
					eng.abort("formula_error", "modify_initiative.amount: %s" % res["error"])
					return
				amount = float(res["value"])
			else:
				amount = float(effect["amount"])
		var micro := int(round(amount * Ruleset.TIME_SCALE))
		match mode:
			"add":
				eng.change_initiative(target, micro, "add", ctx.actor.id, ctx.cause_id)
			"set":
				eng.change_initiative(target, micro - target.initiative_micro, "set", ctx.actor.id, ctx.cause_id)
			"extra_turn":
				eng.change_initiative(target, eng.scheduler.threshold, "extra_turn", ctx.actor.id, ctx.cause_id)
			"steal":
				var taken := mini(maxi(micro, 0), target.initiative_micro)
				eng.change_initiative(target, -taken, "stolen", ctx.actor.id, ctx.cause_id)
				eng.change_initiative(ctx.actor, taken, "steal", ctx.actor.id, ctx.cause_id)
