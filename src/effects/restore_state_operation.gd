class_name RestoreStateOperation
extends EffectOperation
## {"type":"restore_state","key":"anchor","what":["hp","resources"],"consume":true}
## Restaura selectivamente valores anteriores guardados con record_state. Es una
## operacion de combate registrada (cambia el estado con eventos), NO un rebobinado
## del visor, y NO rebobina el RNG. `consume` (true por defecto) borra la instantanea
## tras usarla: regla de no duplicacion. No revive a los muertos. Con `statuses` restaura el
## conjunto de estados guardado (retira los actuales y reaplica los grabados con su duracion restante).

func type_id() -> String:
	return "restore_state"


func allowed_keys() -> Array:
	return ["type", "key", "what", "consume"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = check_types(effect, ["consume"], [], "restore_state")
	if str(effect.get("key", "")) == "":
		errs.append("restore_state: falta 'key'")
	if effect.has("what"):
		if not (effect["what"] is Array) or (effect["what"] as Array).is_empty():
			errs.append("restore_state.what debe ser una lista no vacia")
		else:
			for w in effect["what"]:
				if not RecordStateOperation.WHAT.has(str(w)):
					errs.append("restore_state.what: '%s' no soportado" % str(w))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	var key := str(effect["key"])
	var what: Array = effect.get("what", ["hp", "resources"])
	for t in ctx.targets:
		if eng.is_aborted():
			return
		if not t.alive or not t.stored_states.has(key):
			eng.emit(EventTypes.TARGET_SKIPPED, ctx.actor.id, t.id, {"reason": "sin_estado_guardado:" + key if t.alive else "dead"}, ctx.cause_id)
			continue
		var snap: Dictionary = t.stored_states[key]
		var hp_before := t.hp
		var rec := eng.emit(EventTypes.STATE_RESTORED, ctx.actor.id, t.id, {"key": key, "what": what.duplicate(), "hp_before": hp_before,
			"hp_target": snap.get("hp", null)}, ctx.cause_id)
		if what.has("hp") and snap.has("hp"):
			eng.change_hp(t, minf(float(snap["hp"]), t.hp_max()) - t.hp, "restore", rec.id)
		if what.has("resources") and snap.has("resources"):
			for rid in snap["resources"]:
				var r: ResourceState = t.get_resource(str(rid))
				if r != null:
					eng.change_resource(t, str(rid), float(snap["resources"][rid]) - r.value, "restore", rec.id)
		if what.has("statuses") and snap.has("statuses"):
			# Restaura el conjunto de estados: retira los actuales (incluso no disipables) y reaplica los guardados.
			for st in t.statuses.duplicate():
				eng.status_service.remove(st, "restore", rec.id)
			for sd in snap["statuses"]:
				var src := eng.get_entity(str(sd["source"]))
				var r: Dictionary = eng.status_service.apply(str(sd["id"]), t, src if src != null else ctx.actor, {
					"stacks": int(sd["stacks"]), "magnitude": float(sd["magnitude"]), "duration": sd["duration"], "cause": rec.id})
				if bool(sd.get("inverted", false)) and r["instance"] != null:
					eng.status_service.invert(r["instance"], rec.id)
		if bool(effect.get("consume", true)):
			t.stored_states.erase(key)
		eng.check_death(t, rec.id)
