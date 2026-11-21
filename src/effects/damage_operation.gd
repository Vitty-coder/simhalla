class_name DamageOperation
extends EffectOperation
## Operacion "damage": uno o varios componentes de dano.
##
## {"type":"damage","always_hit":false,"can_crit":true,"crit_bonus":0.0,
##  "components":[{"damage_type":"physical|magical|true","element":"fire",
##                 "formula":"caster.ATK * 1.5","pen_flat":0,"pen_pct":0,"elem_pen":0}]}
##
## Tiradas: segun damage.roll_scope, impacto/critico se tiran una vez por
## (accion, objetivo) o por componente. Siempre desde los flujos "hit"/"crit".

func type_id() -> String:
	return "damage"


func allowed_keys() -> Array:
	return ["type", "always_hit", "can_crit", "crit_bonus", "components"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	errs.append_array(check_types(effect, ["always_hit", "can_crit"], ["crit_bonus"], "damage"))
	var comps: Variant = effect.get("components", null)
	if not (comps is Array) or (comps as Array).is_empty():
		errs.append("damage: 'components' debe ser una lista no vacia")
		return errs
	for i in (comps as Array).size():
		var c: Variant = comps[i]
		if not (c is Dictionary):
			errs.append("damage.components[%d] debe ser un objeto" % i)
			continue
		if not AbilityDef.DAMAGE_TYPES.has(str(c.get("damage_type", ""))):
			errs.append("damage.components[%d].damage_type invalido '%s'" % [i, str(c.get("damage_type", ""))])
		var label := "damage.components[%d]" % i
		errs.append_array(check_keys(c, ["damage_type", "element", "formula", "pen_flat", "pen_pct", "elem_pen"], label))
		errs.append_array(check_types(c, [], ["pen_flat", "pen_pct", "elem_pen"], label))
		if c.has("element") and not (c["element"] is String):
			errs.append("%s.element debe ser texto" % label)
		errs.append_array(validate_formula(c.get("formula", null), label + ".formula"))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	var rules := eng.rules
	var per_component: bool = str(rules.get_path_value("damage.roll_scope")) == "per_component"
	var always_hit: bool = bool(effect.get("always_hit", false))
	var can_crit: bool = bool(effect.get("can_crit", true))
	var crit_bonus: float = float(effect.get("crit_bonus", 0.0))
	var comps: Array = effect["components"]

	for target in ctx.targets:
		if eng.is_aborted():
			return
		if not target.alive:
			eng.emit(EventTypes.TARGET_SKIPPED, ctx.actor.id, target.id, {"reason": "dead"}, ctx.cause_id)
			continue
		for ci in comps.size():
			if eng.is_aborted():
				return
			if not target.alive:
				break # murio durante la accion (multigolpe): se revalida el objetivo
			var roll: Dictionary
			if per_component or not ctx.rolls.has(target.id):
				roll = eng.roll_attack(ctx.actor, target, always_hit, can_crit, crit_bonus, ctx.cause_id)
				if not per_component:
					ctx.rolls[target.id] = roll
			else:
				roll = ctx.rolls[target.id]
			if not roll["hit"]:
				continue
			_apply_component(ctx, target, ci, comps[ci], bool(roll["crit"]))


func _apply_component(ctx: ActionContext, target: CombatEntity, index: int, comp: Dictionary, crit: bool) -> void:
	var eng := ctx.engine
	var fctx := FormulaContext.new(ctx.actor, target, ctx.status)
	var res: Dictionary = eng.eval_formula(str(comp["formula"]), fctx)
	if not res["ok"]:
		eng.abort("formula_error", "damage.components[%d]: %s" % [index, res["error"]])
		return
	var calc := DamageCalculator.compute(eng.rules, ctx.actor, target, comp, float(res["value"]), crit)
	eng.deliver_damage(ctx.actor, target, {
		"component": index, "damage_type": str(comp["damage_type"]), "element": str(comp.get("element", "")),
		"crit": crit, "base": calc["base"], "premitigation": calc["premitigation"],
		"defense_used": calc["defense_used"], "resistance_used": calc["resistance_used"],
		"amount": calc["amount"],
	}, ctx.cause_id)
