class_name DelayedEffectOperation
extends EffectOperation
## {"type":"delayed_effect","delay":3,"effects":[ ...operaciones... ]}
## Programa efectos para liberarse `delay` unidades de tiempo virtual despues
## (dano retrasado, almacenar y liberar efectos). Se aplican sobre los mismos
## objetivos (los muertos se omiten al liberarse). No se admiten
## delayed_effect anidados; limite global `safety.max_scheduled`.

func type_id() -> String:
	return "delayed_effect"


func allowed_keys() -> Array:
	return ["type", "delay", "effects"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if not (effect.get("delay", null) is float or effect.get("delay", null) is int) or float(effect.get("delay", 0)) <= 0.0:
		errs.append("delayed_effect.delay debe ser un numero > 0")
	var subs: Variant = effect.get("effects", null)
	if not (subs is Array) or (subs as Array).is_empty():
		errs.append("delayed_effect.effects debe ser una lista no vacia")
		return errs
	for i in (subs as Array).size():
		if not (subs[i] is Dictionary):
			errs.append("delayed_effect.effects[%d] debe ser un objeto" % i)
			continue
		if str(subs[i].get("type", "")) == "delayed_effect":
			errs.append("delayed_effect.effects[%d]: delayed_effect anidado no admitido" % i)
			continue
		if registry != null:
			for e in registry.validate_effect(subs[i]):
				errs.append("delayed_effect.effects[%d]: %s" % [i, str(e)])
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	if eng.scheduled_count >= eng.rules.max_scheduled():
		eng.emit(EventTypes.LIMIT_REACHED, ctx.actor.id, "", {"limit": "max_scheduled"}, ctx.cause_id)
		return
	var ids: Array = []
	for t in ctx.targets:
		ids.append(t.id)
	if ids.is_empty():
		return
	eng.scheduled_count += 1
	var at: int = eng.scheduler.now + int(round(float(effect["delay"]) * Ruleset.TIME_SCALE))
	var actor_id := ctx.actor.id
	var effects: Array = (effect["effects"] as Array).duplicate(true)
	var cause := ctx.cause_id
	var sch := eng.emit(EventTypes.DELAYED_SCHEDULED, actor_id, ids[0], {"release_at": float(at) / float(Ruleset.TIME_SCALE), "targets": ids}, cause)
	eng.scheduler.schedule(at, func(e: CombatEngine):
		var actor := e.get_entity(actor_id)
		if actor == null:
			return
		var rel := e.emit(EventTypes.DELAYED_RELEASED, actor_id, ids[0], {"targets": ids}, sch.id)
		var c := ActionContext.new()
		c.engine = e
		c.actor = actor
		c.cause_id = rel.id
		for tid in ids:
			var te := e.get_entity(str(tid))
			if te != null:
				c.targets.append(te)
		ActionResolver.run_effects(e, c, effects), "delayed_effect", {"actor": actor_id})
