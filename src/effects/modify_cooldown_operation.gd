class_name ModifyCooldownOperation
extends EffectOperation
## {"type":"modify_cooldown","ability":"id"(opcional=todas),"mode":"reduce|add|reset","amount":1}
## reduce/add cambian lo que resta (en la unidad del cooldown; <= 0 lo elimina); reset lo elimina.

func type_id() -> String:
	return "modify_cooldown"


func allowed_keys() -> Array:
	return ["type", "ability", "mode", "amount"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	var mode := str(effect.get("mode", ""))
	if not ["reduce", "add", "reset"].has(mode):
		errs.append("modify_cooldown.mode debe ser reduce, add o reset")
	elif mode != "reset" and (not (effect.get("amount", null) is float or effect.get("amount", null) is int) or float(effect.get("amount", 0)) <= 0.0):
		errs.append("modify_cooldown.amount debe ser un numero > 0")
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	var mode := str(effect["mode"])
	for t in ctx.targets:
		var ids: Array = [str(effect["ability"])] if effect.has("ability") else t.cooldowns.keys()
		for aid in ids:
			if not t.cooldowns.has(aid):
				continue
			var du: Duration = t.cooldowns[aid]
			var by := float(effect.get("amount", 0.0))
			if mode == "reset":
				t.cooldowns.erase(aid)
			elif du.unit == "time":
				du.expires_at += int(round((by if mode == "add" else -by) * Ruleset.TIME_SCALE))
				if du.expires_at <= eng.scheduler.now:
					t.cooldowns.erase(aid)
			else:
				du.remaining += by if mode == "add" else -by
				if du.remaining <= 0.0:
					t.cooldowns.erase(aid)
			eng.emit(EventTypes.STATUS_CHANGED, ctx.actor.id, t.id, {"cooldown": aid, "change": mode, "left": t.cooldowns.has(aid)}, ctx.cause_id)
