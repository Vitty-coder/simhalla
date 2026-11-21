class_name HealOperation
extends EffectOperation
## Operacion "heal": {"type":"heal","formula":"caster.MAG * 0.8","can_crit":false}
##
## Curacion efectiva = redondeo(raw * HEAL_REC del receptor), limitada a la vida
## faltante; el exceso se registra como overheal. El critico solo se aplica si
## el efecto lo autoriza (can_crit), usando CRIT del lanzador y CRIT_DMG.

func type_id() -> String:
	return "heal"


func allowed_keys() -> Array:
	return ["type", "formula", "can_crit"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = check_types(effect, ["can_crit"], [], "heal")
	errs.append_array(validate_formula(effect.get("formula", null), "heal.formula"))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	var can_crit: bool = bool(effect.get("can_crit", false))
	for target in ctx.targets:
		if eng.is_aborted():
			return
		if not target.alive:
			eng.emit(EventTypes.TARGET_SKIPPED, ctx.actor.id, target.id, {"reason": "dead"}, ctx.cause_id)
			continue
		var res: Dictionary = eng.eval_formula(str(effect["formula"]), FormulaContext.new(ctx.actor, target, ctx.status))
		if not res["ok"]:
			eng.abort("formula_error", "heal: %s" % res["error"])
			return
		var raw: float = float(res["value"])
		var crit := false
		if can_crit:
			var chance: float = DamageCalculator.crit_chance(eng.rules, ctx.actor)
			var roll: float = eng.rng.stream("crit").next_float()
			crit = roll < chance
			if crit:
				eng.emit(EventTypes.CRIT, ctx.actor.id, target.id, {"chance": chance, "roll": roll, "kind": "heal"}, ctx.cause_id)
				raw *= maxf(ctx.actor.stats.get_value("CRIT_DMG"), 0.0)
		var amount: float = DamageCalculator.heal_amount(eng.rules, target, raw)
		var pre := eng.emit(EventTypes.HEAL_PRE, ctx.actor.id, target.id, {
			"raw": raw, "amount": amount, "crit": crit,
		}, ctx.cause_id, CombatEvent.Phase.PRE)
		if pre.cancelled:
			continue
		amount = maxf(float(pre.data["amount"]), 0.0)
		var missing: float = maxf(target.hp_max() - target.hp, 0.0)
		var applied: float = minf(amount, missing)
		var done := eng.emit(EventTypes.HEAL_DONE, ctx.actor.id, target.id, {
			"raw": raw, "amount": amount, "applied": applied, "overheal": amount - applied,
			"crit": crit, "hp_before": target.hp, "hp_after": target.hp + applied,
		}, pre.id, CombatEvent.Phase.POST)
		eng.change_hp(target, applied, "heal", done.id)
