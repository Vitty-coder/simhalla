class_name CopyActionOperation
extends EffectOperation
## {"type":"copy_action"}: el lanzador usa contra el objetivo la ultima habilidad que
## el OBJETIVO utilizo (aunque el lanzador no la posea). Gratis: sin hueco, costes ni
## cooldown (provisional, D-045). No copia habilidades canalizadas ni disparadas.

func type_id() -> String:
	return "copy_action"


func allowed_keys() -> Array:
	return ["type"]


func resolve(ctx: ActionContext, _effect: Dictionary) -> void:
	var eng := ctx.engine
	for t in ctx.targets:
		if eng.is_aborted():
			return
		var last: Dictionary = t.last_action
		var ab: AbilityDef = t.get_ability(str(last.get("ability", ""))) if not last.is_empty() else null
		if ab == null or ab.cast_time > 0.0 or ab.is_triggered() or not t.alive:
			eng.emit(EventTypes.TARGET_SKIPPED, ctx.actor.id, t.id, {"reason": "nada_que_copiar"}, ctx.cause_id)
			continue
		var targets: Array[CombatEntity] = [t]
		ActionResolver.resolve_free(eng, ctx.actor, ab, targets, ctx.cause_id, "copy")
