class_name TransferStatusOperation
extends EffectOperation
## Mueve o copia estados entre el lanzador y los objetivos:
##   {"type":"transfer_status","mode":"steal|copy|give","status":"id" | "tags":[..] | "beneficial":bool,"count":n}
##   steal: del objetivo al lanzador (lo pierde el objetivo)   copy: copia al lanzador
##   give:  del lanzador al objetivo (lo pierde el lanzador)
## Conserva pilas, magnitud y duracion restante; el origen original se mantiene.

func type_id() -> String:
	return "transfer_status"


func allowed_keys() -> Array:
	return ["type", "mode", "status", "tags", "beneficial", "count"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if not ["steal", "copy", "give"].has(str(effect.get("mode", ""))):
		errs.append("transfer_status.mode debe ser steal, copy o give")
	if not (effect.has("status") or effect.has("tags") or effect.has("beneficial")):
		errs.append("transfer_status: indique 'status', 'tags' o 'beneficial'")
	if effect.has("count") and (not (effect["count"] is float or effect["count"] is int) or int(effect["count"]) < 1):
		errs.append("transfer_status.count debe ser un entero >= 1")
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	var svc := eng.status_service
	var mode := str(effect["mode"])
	for target in ctx.targets:
		if eng.is_aborted():
			return
		var from_e: CombatEntity = ctx.actor if mode == "give" else target
		var to_e: CombatEntity = target if mode == "give" else ctx.actor
		if from_e == to_e:
			continue
		var found := svc.matching(from_e, effect)
		var limit: int = int(effect.get("count", 9999))
		for inst in found:
			if limit <= 0:
				break
			limit -= 1
			var spec: Variant = _spec(eng, inst)
			var data := {"stacks": inst.stacks, "magnitude": inst.magnitude, "duration": spec, "cause": ctx.cause_id}
			var src := eng.get_entity(inst.source_id)
			if mode != "copy":
				svc.remove(inst, "transferred", ctx.cause_id)
			svc.apply(inst.def.id, to_e, src if src != null else ctx.actor, data)


static func _spec(eng: CombatEngine, inst: StatusInstance) -> Variant:
	var du := inst.duration
	if du.is_permanent():
		return {"unit": "permanent"}
	if du.unit == "time":
		return {"unit": "time", "amount": maxf(float(du.expires_at - eng.scheduler.now) / float(Ruleset.TIME_SCALE), 0.001)}
	var d := {"unit": du.unit, "amount": maxf(du.remaining, 1.0)}
	if du.unit == "events":
		d["event"] = du.event_type
		d["filter"] = du.event_filter.duplicate()
	return d
