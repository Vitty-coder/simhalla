class_name PropagateStatusOperation
extends EffectOperation
## Propaga copias de los estados del objetivo a otras entidades:
##   {"type":"propagate_status","status":"plague" | "tags":[..],"to":"target_allies","count":2}
## `to` (relativo al OBJETIVO salvo caster_*): target_allies (su equipo, sin el), target_enemies,
## caster_allies, caster_enemies (relativos al lanzador), all_others, random_other.
## `count` limita los receptores (orden por slot; random_other usa el flujo "select").
## Conserva pilas, magnitud, duracion restante y origen. Colocada en `on_expire` o
## `on_death` de un estado, hace que se extienda al expirar o al morir el afectado.

const TARGETS := ["target_allies", "target_enemies", "caster_allies", "caster_enemies", "all_others", "random_other"]


func type_id() -> String:
	return "propagate_status"


func allowed_keys() -> Array:
	return ["type", "status", "tags", "to", "count"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if not (effect.has("status") or effect.has("tags")):
		errs.append("propagate_status: indique 'status' o 'tags'")
	if not TARGETS.has(str(effect.get("to", ""))):
		errs.append("propagate_status.to debe ser uno de: %s" % ", ".join(TARGETS))
	if effect.has("count") and (not (effect["count"] is float or effect["count"] is int) or int(effect["count"]) < 1):
		errs.append("propagate_status.count debe ser un entero >= 1")
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	var svc := eng.status_service
	for src_e in ctx.targets:
		if eng.is_aborted():
			return
		var found := svc.matching(src_e, effect)
		# En on_expire el estado ya no esta en el portador: se incluye el propio estado en curso.
		var cur := ctx.status
		if cur != null and cur.holder_id == src_e.id and not found.has(cur) and StatusService._matches(cur, effect):
			found.append(cur)
		if found.is_empty():
			continue
		var pool: Array[CombatEntity] = []
		var to := str(effect["to"])
		for o in eng.entities:
			if not o.alive or o == src_e:
				continue
			match to:
				"target_allies":
					if eng.relation(src_e, o) == "ally":
						pool.append(o)
				"target_enemies":
					if eng.relation(src_e, o) == "enemy":
						pool.append(o)
				"caster_allies":
					if eng.relation(ctx.actor, o) != "enemy":
						pool.append(o)
				"caster_enemies":
					if eng.relation(ctx.actor, o) == "enemy":
						pool.append(o)
				_:
					pool.append(o)
		if to == "random_other" and not pool.is_empty():
			pool = [pool[eng.rng.stream("select").next_int(pool.size())]]
		var limit: int = int(effect.get("count", 9999))
		for r in pool:
			if limit <= 0:
				break
			limit -= 1
			for inst in found:
				var src := eng.get_entity(inst.source_id)
				svc.apply(inst.def.id, r, src if src != null else ctx.actor, {
					"stacks": inst.stacks, "magnitude": inst.magnitude,
					"duration": TransferStatusOperation._spec(eng, inst), "cause": ctx.cause_id,
				})
