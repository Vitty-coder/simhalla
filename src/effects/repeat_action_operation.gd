class_name RepeatActionOperation
extends EffectOperation
## {"type":"repeat_action","times":1}: el lanzador repite su accion anterior (ability
## y objetivos aun validos) sin gastar hueco, costes ni cooldown (provisional, D-045).

func type_id() -> String:
	return "repeat_action"


func allowed_keys() -> Array:
	return ["type", "times"]


func validate(effect: Dictionary) -> Array:
	if effect.has("times") and (not (effect["times"] is float or effect["times"] is int) or int(effect["times"]) < 1 or int(effect["times"]) > 3):
		return ["repeat_action.times debe ser un entero entre 1 y 3"]
	return []


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	var prev: Dictionary = ctx.actor.prev_action
	if prev.is_empty():
		eng.emit(EventTypes.TARGET_SKIPPED, ctx.actor.id, "", {"reason": "sin_accion_previa"}, ctx.cause_id)
		return
	var ab := ctx.actor.get_ability(str(prev["ability"]))
	if ab == null or ab.cast_time > 0.0:
		return
	for i in int(effect.get("times", 1)):
		var targets: Array[CombatEntity] = []
		for tid in prev["targets"]:
			var t := eng.get_entity(str(tid))
			if t != null and t.alive:
				targets.append(t)
		if targets.is_empty() or eng.is_aborted():
			return
		ActionResolver.resolve_free(eng, ctx.actor, ab, targets, ctx.cause_id, "repeat")
