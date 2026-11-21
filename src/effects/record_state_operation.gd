class_name RecordStateOperation
extends EffectOperation
## {"type":"record_state","key":"anchor","what":["hp","resources"]}
## Guarda una instantanea (vida, recursos y/o estados) del objetivo bajo `key` para una
## restauracion posterior. Re-grabar la misma clave la sustituye.

const WHAT := ["hp", "resources", "statuses"]


func type_id() -> String:
	return "record_state"


func allowed_keys() -> Array:
	return ["type", "key", "what"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if not (effect.get("key", null) is String) or not RegEx.create_from_string("^[a-z][a-z0-9_]{0,31}$").search(str(effect.get("key", ""))):
		errs.append("record_state.key debe ser un identificador en minusculas")
	if effect.has("what"):
		if not (effect["what"] is Array) or (effect["what"] as Array).is_empty():
			errs.append("record_state.what debe ser una lista no vacia")
		else:
			for w in effect["what"]:
				if not WHAT.has(str(w)):
					errs.append("record_state.what: '%s' no soportado (use %s)" % [str(w), ", ".join(WHAT)])
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var eng := ctx.engine
	var what: Array = effect.get("what", ["hp", "resources"])
	for t in ctx.targets:
		if not t.alive:
			continue
		var snap := {"time": eng.scheduler.now}
		if what.has("hp"):
			snap["hp"] = t.hp
		if what.has("resources"):
			var rs := {}
			for rid in t.resources:
				rs[rid] = (t.resources[rid] as ResourceState).value
			snap["resources"] = rs
		if what.has("statuses"):
			var sl: Array = []
			for st in t.statuses:
				sl.append({"id": st.def.id, "stacks": st.stacks, "magnitude": st.magnitude, "source": st.source_id,
					"inverted": st.inverted, "duration": TransferStatusOperation._spec(eng, st)})
			snap["statuses"] = sl
		t.stored_states[str(effect["key"])] = snap
		eng.emit(EventTypes.STATE_RECORDED, ctx.actor.id, t.id, {"key": str(effect["key"]), "what": what.duplicate(),
			"hp": snap.get("hp", null)}, ctx.cause_id)
