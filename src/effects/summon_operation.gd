class_name SummonOperation
extends EffectOperation
## {"type":"summon","template":"wolf","count":1,"lifespan":3 | {unit,amount},"inherit":{"stat_pct":{"ATK":0.5}}}
## Crea entidades completas (HP, stats, ATB, habilidades, IA propias) a partir de
## `summons.<template>` del PJ. Mismo equipo que el invocador; `owner_id` = invocador;
## `counts_for_victory` = false salvo que la plantilla lo indique. Limites: por
## invocador y en total (reglamento `summons.*`), y profundidad 3. Al morir el
## dueno las invocaciones desaparecen (`summons.on_owner_death`).

func type_id() -> String:
	return "summon"


func allowed_keys() -> Array:
	return ["type", "template", "count", "lifespan", "inherit"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if str(effect.get("template", "")) == "":
		errs.append("summon: falta 'template'")
	if effect.has("count") and (not (effect["count"] is float or effect["count"] is int) or int(effect["count"]) < 1 or int(effect["count"]) > 8):
		errs.append("summon.count debe ser un entero entre 1 y 8")
	if effect.has("lifespan"):
		errs.append_array(Duration.validate(effect["lifespan"], "summon.lifespan"))
		if effect["lifespan"] is Dictionary and str(effect["lifespan"].get("unit", "target_turns")) in ["caster_turns", "events"]:
			errs.append("summon.lifespan: unit no admitida (use target_turns, global_actions, time o permanent)")
	if effect.has("inherit"):
		var inh: Variant = effect["inherit"]
		if not (inh is Dictionary):
			errs.append("summon.inherit debe ser un objeto")
		else:
			for k in inh:
				if str(k) != "stat_pct":
					errs.append("summon.inherit.%s desconocido" % str(k))
			var sp: Variant = inh.get("stat_pct", {})
			if not (sp is Dictionary):
				errs.append("summon.inherit.stat_pct debe ser un objeto")
			else:
				for st in sp:
					if not (sp[st] is float or sp[st] is int) or float(sp[st]) < 0.0:
						errs.append("summon.inherit.stat_pct.%s debe ser un numero >= 0" % str(st))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	var owner := ctx.actor
	var template := str(effect["template"])
	if not owner.summon_templates.has(template):
		eng.abort("summon_invalid", "plantilla de invocacion desconocida '%s'" % template)
		return
	for i in int(effect.get("count", 1)):
		if eng.is_aborted():
			return
		if owner.summon_depth >= 3:
			eng.emit(EventTypes.LIMIT_REACHED, owner.id, "", {"limit": "summon_depth", "template": template}, ctx.cause_id)
			return
		if eng.owned_alive(owner).size() >= int(eng.rules.get_path_value("summons.max_per_owner")):
			eng.emit(EventTypes.LIMIT_REACHED, owner.id, "", {"limit": "summons_per_owner", "template": template}, ctx.cause_id)
			return
		if eng.entities.size() >= eng.rules.max_entities():
			eng.emit(EventTypes.LIMIT_REACHED, owner.id, "", {"limit": "max_entities", "template": template}, ctx.cause_id)
			return
		var data: Dictionary = (owner.summon_templates[template] as Dictionary).duplicate(true)
		eng.summon_counter += 1
		data["id"] = "%s#%s%d" % [owner.id, template, eng.summon_counter]
		data["team"] = owner.team
		data["counts_for_victory"] = bool(data.get("counts_for_victory", false))
		var b := EntityFactory.build(data, eng.profile, eng.rules, eng.registry)
		if b["entity"] == null:
			eng.abort("summon_invalid", "invocacion '%s': %s" % [template, "; ".join(b["errors"])])
			return
		var ent: CombatEntity = b["entity"]
		ent.owner_id = owner.id
		ent.summon_depth = owner.summon_depth + 1
		ent.content_ref = {"template": template}
		var sp: Dictionary = effect.get("inherit", {}).get("stat_pct", {})
		for st in sp:
			ent.stats.set_base(str(st), owner.stats.get_value(str(st)) * float(sp[st]))
		if effect.has("lifespan"):
			ent.lifespan = Duration.from_dict(effect["lifespan"])
			if ent.lifespan.is_permanent():
				ent.lifespan = null
		if eng.add_entity(ent, ctx.cause_id) == null:
			return
		if ent.lifespan != null and ent.lifespan.unit == "time":
			var eid := ent.id
			eng.scheduler.schedule(eng.scheduler.now + int(round(ent.lifespan.amount * Ruleset.TIME_SCALE)),
				func(e: CombatEngine): e.despawn(e.get_entity(eid), "lifespan", 0), "summon_lifespan", {"entity": eid})
			ent.lifespan = null
