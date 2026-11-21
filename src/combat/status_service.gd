class_name StatusService
extends RefCounted
## Estados, duraciones, cooldowns, regeneracion y efectos periodicos.
##
## Se engancha al motor SOLO mediante eventos (observadores/interceptores) y
## temporizadores del planificador. Todo cambio emite eventos trazables.
## Convenciones de tiempo: ver Duration (D-040).

const INTERCEPT_PRIO := -500

var engine: CombatEngine
var _seq: int = 0
var _tick_depth: int = 0


func _init(eng: CombatEngine) -> void:
	engine = eng


func attach() -> void:
	engine.dispatcher.observe("*", Callable(self, "_on_event"), -900, "status_service")
	engine.dispatcher.intercept(EventTypes.TURN_STARTED, Callable(self, "_intercept_turn"), INTERCEPT_PRIO, "status_service")


func _intercept_turn(ev: CombatEvent, _eng: CombatEngine) -> void:
	var e := engine.get_entity(ev.source_id)
	if e != null and e.has_status_flag("skip_turn"):
		for st in e.statuses:
			if st.def.flags.get("skip_turn", false):
				ev.cancel("status:" + st.def.id, "turno omitido por estado")
				return


# --- Aplicacion -------------------------------------------------------------------------------

## opts: {"duration": spec, "stacks": int, "magnitude": float, "cause": int}.
## Devuelve {"result": applied|stacked|refreshed|extended|replaced|ignored|rejected, "instance": StatusInstance|null}
func apply(status_id: String, holder: CombatEntity, source: CombatEntity, opts: Dictionary = {}) -> Dictionary:
	var def := engine.catalog.get_def(status_id)
	var cause: int = int(opts.get("cause", 0))
	var src_id: String = source.id if source != null else ""
	if def == null:
		engine.abort("unknown_status", "estado desconocido '%s'" % status_id)
		return {"result": "rejected", "instance": null}
	if not holder.alive:
		return _reject(def, holder, src_id, "dead", cause)
	for st in holder.statuses:
		if st.frozen:
			continue
		for tag in st.def.flags.get("immune_status_tags", []):
			if def.tags.has(str(tag)):
				return _reject(def, holder, src_id, "immune:" + st.def.id, cause)
	var stacks: int = maxi(int(opts.get("stacks", 1)), 1)
	var magnitude: float = float(opts.get("magnitude", 1.0))
	var spec: Variant = opts.get("duration", def.duration_spec)
	var existing: Array[StatusInstance] = []
	for st in holder.statuses:
		if st.def.id == def.id:
			existing.append(st)

	if not existing.is_empty():
		match def.policy:
			"ignore":
				return _reject(def, holder, src_id, "ignored_existing", cause)
			"keep_strongest":
				var best := existing[0]
				for st in existing:
					if st.strength() > best.strength():
						best = st
				if float(stacks) * magnitude <= best.strength():
					return _reject(def, holder, src_id, "weaker", cause)
				remove(best, "replaced", cause)
			"replace":
				for st in existing:
					remove(st, "replaced", cause)
			"stack_intensity":
				return _change_existing(existing[0], def, source, stacks, magnitude, spec, "stack_intensity", cause)
			"stack_duration":
				return _change_existing(existing[0], def, source, 0, magnitude, spec, "stack_duration", cause)
			"refresh":
				return _change_existing(existing[0], def, source, 0, magnitude, spec, "refresh", cause)
			"independent":
				if existing.size() >= def.max_stacks:
					return _reject(def, holder, src_id, "max_instances", cause)
	if def.group != "":
		for st in holder.statuses.duplicate():
			if st.def.group == def.group and st.def.id != def.id:
				remove(st, "replaced_group", cause)

	var du := Duration.from_dict(spec)
	var pre := engine.emit(EventTypes.STATUS_APPLIED, src_id, holder.id, {
		"status": def.id, "stacks": mini(stacks, def.max_stacks), "magnitude": magnitude, "duration": du.to_dict(), "policy": def.policy,
	}, cause, CombatEvent.Phase.PRE)
	if pre.cancelled:
		return {"result": "rejected", "instance": null}
	_seq += 1
	var inst := StatusInstance.new()
	inst.def = def
	inst.holder_id = holder.id
	inst.source_id = src_id
	inst.seq = _seq
	inst.stacks = mini(stacks, def.max_stacks)
	inst.magnitude = float(pre.data.get("magnitude", magnitude))
	inst.duration = du
	inst.applied_cause = cause
	inst.applied_turn = engine.turn_count
	inst.modifier_source = "status:%s#%d" % [def.id, inst.seq]
	_init_duration(inst, holder, source)
	holder.statuses.append(inst)
	recompute_modifiers(inst, holder)
	var absorb: Variant = def.defense.get("absorb", null)
	if absorb is Dictionary:
		var r := engine.eval_formula(str(absorb["amount"]), FormulaContext.new(source if source != null else holder, holder, inst))
		if not r["ok"]:
			engine.abort("formula_error", "estado '%s' defense.absorb.amount: %s" % [def.id, r["error"]])
			return {"result": "rejected", "instance": null}
		inst.shield = maxf(float(r["value"]), 0.0)
	if def.flags.get("suspend_initiative", false):
		holder.suspension_sources["status:%d" % inst.seq] = true
	if not def.form.is_empty():
		_apply_form(inst, holder)
	if def.flags.get("interrupt_channel", false):
		engine.interrupt_channel(holder, "status:" + def.id)
	if not def.on_apply.is_empty():
		run_effects(def.on_apply, source, holder, inst, pre.id)
	if not def.flags.get("suspend_statuses", []).is_empty():
		refresh_suspension(holder)
	elif _is_frozen_by_others(holder, inst):
		refresh_suspension(holder)
	engine.emit(EventTypes.STATUS_GAINED, src_id, holder.id, {"status": def.id, "stacks": inst.stacks, "magnitude": inst.magnitude}, pre.id)
	return {"result": "applied", "instance": inst}


func _reject(def: StatusDef, holder: CombatEntity, src_id: String, reason: String, cause: int) -> Dictionary:
	engine.emit(EventTypes.STATUS_REJECTED, src_id, holder.id, {"status": def.id, "reason": reason}, cause)
	return {"result": "rejected", "instance": null}


func _change_existing(inst: StatusInstance, def: StatusDef, source: CombatEntity, stacks: int, magnitude: float, spec: Variant, change: String, cause: int) -> Dictionary:
	var holder := engine.get_entity(inst.holder_id)
	var before := inst.to_dict()
	var result := "refreshed"
	match change:
		"stack_intensity":
			inst.stacks = mini(inst.stacks + stacks, def.max_stacks)
			inst.magnitude = maxf(inst.magnitude, magnitude)
			_reset_duration(inst, holder, source, spec)
			result = "stacked"
			recompute_modifiers(inst, holder)
		"stack_duration":
			var add := Duration.from_dict(spec)
			_extend_duration(inst, holder, add.amount)
			result = "extended"
		"refresh":
			inst.magnitude = maxf(inst.magnitude, magnitude)
			_reset_duration(inst, holder, source, spec)
	engine.emit(EventTypes.STATUS_CHANGED, source.id if source != null else "", holder.id, {
		"status": def.id, "change": change, "before": before, "after": inst.to_dict(),
	}, cause)
	return {"result": result, "instance": inst}


# --- Duraciones ----------------------------------------------------------------------------------

func _init_duration(inst: StatusInstance, holder: CombatEntity, source: CombatEntity) -> void:
	var du := inst.duration
	match du.unit:
		"target_turns":
			if engine.turn != null and engine.turn.entity == holder:
				du.skip_turn = engine.turn.number
		"caster_turns":
			if engine.turn != null and source != null and engine.turn.entity == source:
				du.skip_turn = engine.turn.number
		"global_actions":
			du.skip_cause = inst.applied_cause
		"time":
			_arm_timer(inst, holder, int(engine.scheduler.now) + int(round(du.amount * Ruleset.TIME_SCALE)))


func _arm_timer(inst: StatusInstance, holder: CombatEntity, at: int) -> void:
	if inst.timer_seq >= 0:
		engine.scheduler.cancel_timed(inst.timer_seq)
	inst.duration.expires_at = at
	var iid := inst.seq
	inst.timer_seq = engine.scheduler.schedule(at, func(_e):
		var cur := _find(holder, iid)
		if cur != null:
			remove(cur, "expired", 0), "status_expiry", {"status": inst.def.id})


func _reset_duration(inst: StatusInstance, holder: CombatEntity, source: CombatEntity, spec: Variant) -> void:
	var fresh := Duration.from_dict(spec)
	inst.duration.unit = fresh.unit
	inst.duration.amount = fresh.amount
	inst.duration.remaining = fresh.amount
	inst.duration.event_type = fresh.event_type
	inst.duration.event_filter = fresh.event_filter
	_init_duration(inst, holder, source)


func _extend_duration(inst: StatusInstance, holder: CombatEntity, by: float) -> void:
	var du := inst.duration
	if du.is_permanent():
		return
	if du.unit == "time":
		var at := du.expires_at + int(round(by * Ruleset.TIME_SCALE))
		if at <= engine.scheduler.now:
			remove(inst, "expired", 0)
			return
		du.amount = maxf(du.amount + by, 0.0)
		_arm_timer(inst, holder, at)
	else:
		du.extend(by)
		if du.remaining <= 0.0:
			remove(inst, "expired", 0)


## Ajusta la duracion restante de un estado (extend_status): positivo alarga, negativo acorta.
func adjust_duration(inst: StatusInstance, by: float) -> void:
	_extend_duration(inst, engine.get_entity(inst.holder_id), by)
	var holder := engine.get_entity(inst.holder_id)
	if holder != null and _find(holder, inst.seq) != null:
		engine.emit(EventTypes.STATUS_CHANGED, "", holder.id, {"status": inst.def.id, "change": "duration", "after": inst.to_dict()}, 0)


func _find(holder: CombatEntity, seq: int) -> StatusInstance:
	for st in holder.statuses:
		if st.seq == seq:
			return st
	return null


# --- Modificadores ----------------------------------------------------------------------------------

func recompute_modifiers(inst: StatusInstance, holder: CombatEntity) -> void:
	holder.stats.remove_by_source(inst.modifier_source)
	if not inst.frozen:
		for m in inst.def.modifiers:
			var kind: StatModifier.Kind = StatusDef.KINDS[str(m["kind"])]
			var v: float = float(m["value"])
			if bool(m.get("per_stack", true)):
				match kind:
					StatModifier.Kind.FLAT, StatModifier.Kind.PCT_ADD:
						v *= float(inst.stacks)
					StatModifier.Kind.MULT:
						v = pow(v, float(inst.stacks))
			if inst.inverted:
				match kind:
					StatModifier.Kind.FLAT, StatModifier.Kind.PCT_ADD:
						v = -v
					StatModifier.Kind.MULT:
						v = 1.0 / v if v != 0.0 else 1.0
			holder.stats.add_modifier(StatModifier.make(str(m["stat"]), kind, v, inst.modifier_source, int(m.get("priority", 0))))
	engine.clamp_hp(holder)


# --- Inversion y suspension --------------------------------------------------------------------------

## Invierte los efectos de un estado: modificadores (flat/pct_add se niegan, mult se invierte) y
## efectos periodicos (dano <-> curacion). Invertir de nuevo lo deshace. Cuenta como "beneficial" al reves.
func invert(inst: StatusInstance, cause: int = 0) -> void:
	var holder := engine.get_entity(inst.holder_id)
	if holder == null or not holder.statuses.has(inst):
		return
	inst.inverted = not inst.inverted
	recompute_modifiers(inst, holder)
	engine.emit(EventTypes.STATUS_CHANGED, "", holder.id, {"status": inst.def.id, "change": "inverted" if inst.inverted else "restored", "after": inst.to_dict()}, cause)


## Convierte un efecto periodico en su inverso: damage -> heal (suma de componentes), heal -> damage verdadero.
static func invert_effect(ef: Dictionary) -> Dictionary:
	var out: Dictionary = ef.duplicate(true)
	match str(ef.get("type", "")):
		"damage":
			var parts: Array = []
			for c in ef["components"]:
				parts.append("(%s)" % str(c["formula"]))
			out = {"type": "heal", "formula": " + ".join(parts), "can_crit": false}
		"heal":
			out = {"type": "damage", "always_hit": true, "can_crit": false,
				"components": [{"damage_type": "true", "formula": str(ef["formula"])}]}
		_:
			return out
	for k in ["on", "chance"]:
		if ef.has(k):
			out[k] = ef[k]
	return out


func _is_frozen_by_others(holder: CombatEntity, inst: StatusInstance) -> bool:
	for other in holder.statuses:
		if other == inst or other.frozen:
			continue
		var tags: Array = other.def.flags.get("suspend_statuses", [])
		if tags.is_empty():
			continue
		if tags.has("*"):
			return true
		for t in inst.def.tags:
			if tags.has(t):
				return true
	return false


## Recalcula que estados estan suspendidos (por `suspend_statuses` de otros) y sincroniza
## modificadores, suspension de iniciativa y temporizadores de duracion por tiempo.
func refresh_suspension(holder: CombatEntity) -> void:
	for _pass in 3:
		var changed := false
		for inst: StatusInstance in holder.statuses.duplicate():
			var want := _is_frozen_by_others(holder, inst)
			if want == inst.frozen:
				continue
			changed = true
			inst.frozen = want
			var du := inst.duration
			if want:
				if du.unit == "time" and inst.timer_seq >= 0:
					inst.frozen_time_left = maxi(du.expires_at - engine.scheduler.now, 0)
					engine.scheduler.cancel_timed(inst.timer_seq)
					inst.timer_seq = -1
				holder.suspension_sources.erase("status:%d" % inst.seq)
			else:
				if du.unit == "time" and inst.frozen_time_left >= 0:
					_arm_timer(inst, holder, engine.scheduler.now + inst.frozen_time_left)
					inst.frozen_time_left = -1
				if inst.def.flags.get("suspend_initiative", false):
					holder.suspension_sources["status:%d" % inst.seq] = true
			recompute_modifiers(inst, holder)
			engine.emit(EventTypes.STATUS_CHANGED, "", holder.id, {"status": inst.def.id, "change": "suspended" if want else "resumed", "after": inst.to_dict()}, 0)
		if not changed:
			return


# --- Retirada -----------------------------------------------------------------------------------------

func remove(inst: StatusInstance, reason: String, cause: int = 0) -> void:
	var holder := engine.get_entity(inst.holder_id)
	if holder == null or not holder.statuses.has(inst):
		return
	holder.statuses.erase(inst)
	holder.stats.remove_by_source(inst.modifier_source)
	if inst.timer_seq >= 0:
		engine.scheduler.cancel_timed(inst.timer_seq)
		inst.timer_seq = -1
	holder.suspension_sources.erase("status:%d" % inst.seq)
	if not inst.def.form.is_empty():
		_revert_form(inst, holder)
	var type := EventTypes.STATUS_EXPIRED if reason == "expired" else EventTypes.STATUS_REMOVED
	engine.emit(type, inst.source_id, holder.id, {"status": inst.def.id, "reason": reason, "stacks": inst.stacks}, cause)
	if not inst.def.flags.get("suspend_statuses", []).is_empty():
		refresh_suspension(holder)
	engine.clamp_hp(holder)
	if reason == "expired" and not inst.def.on_expire.is_empty() and holder.alive:
		run_effects(inst.def.on_expire, engine.get_entity(inst.source_id), holder, inst, cause)


func clear_all(holder: CombatEntity, reason: String) -> void:
	if reason == "death":
		# efectos al morir (p. ej. propagar el estado) antes de retirarlos
		for st in holder.statuses.duplicate():
			if not st.def.on_death.is_empty() and not st.frozen:
				run_effects(st.def.on_death, engine.get_entity(st.source_id), holder, st, 0)
	for st in holder.statuses.duplicate():
		remove(st, reason, 0)


## Retira estados que cumplan el filtro: {"status": id, "tags": [..], "beneficial": bool, "count": n, "force": bool}.
## Devuelve las instancias retiradas. Respeta `dispellable` salvo force.
func dispel(holder: CombatEntity, filter: Dictionary, reason: String, cause: int) -> Array:
	var removed: Array = []
	var limit: int = int(filter.get("count", 9999))
	for st in holder.statuses.duplicate():
		if removed.size() >= limit:
			break
		if not _matches(st, filter):
			continue
		if not st.def.dispellable and not bool(filter.get("force", false)):
			continue
		remove(st, reason, cause)
		removed.append(st)
	return removed


static func _matches(st: StatusInstance, filter: Dictionary) -> bool:
	if filter.has("status") and st.def.id != str(filter["status"]):
		return false
	if filter.has("tags"):
		var ok := false
		for t in filter["tags"]:
			if st.def.tags.has(str(t)):
				ok = true
		if not ok:
			return false
	if filter.has("beneficial") and (st.def.beneficial != st.inverted) != bool(filter["beneficial"]):
		return false
	return true


func matching(holder: CombatEntity, filter: Dictionary) -> Array:
	var out: Array = []
	for st in holder.statuses:
		if _matches(st, filter):
			out.append(st)
	return out


# --- Formas (transformaciones) -----------------------------------------------------------------------

func _apply_form(inst: StatusInstance, holder: CombatEntity) -> void:
	var fm: Dictionary = inst.def.form
	var saved := {"added": [], "removed": [], "ai": holder.ai}
	for aid in fm.get("remove_abilities", []):
		var old := holder.get_ability(str(aid))
		if old != null:
			saved["removed"].append(old)
			engine.remove_ability(holder, str(aid))
	for ad in fm.get("add_abilities", []):
		var r := AbilityDef.from_dict(ad, engine.registry)
		if r["ability"] != null and holder.get_ability(str((r["ability"] as AbilityDef).id)) == null:
			engine.add_ability(holder, r["ability"], "form:" + inst.def.id)
			saved["added"].append((r["ability"] as AbilityDef).id)
	if fm.has("ai"):
		var ai := AIFactory.build(fm["ai"])
		if ai["ai"] != null:
			holder.ai = ai["ai"]
			var berr: Array = holder.ai.bind_scripts(holder.scripts, ScriptLimits.from_ruleset(engine.rules))
			if not berr.is_empty():
				holder.ai = saved["ai"] # una forma con un script de IA invalido no cambia la IA
				engine.emit(EventTypes.AI_FALLBACK, holder.id, "", {"reason": "form_script: " + str(berr[0]), "policy": "keep"}, 0)
			AIMemory.ensure(engine, holder.ai)
	inst.form_applied = saved
	engine.emit(EventTypes.TRANSFORMED, inst.source_id, holder.id, {"form": inst.def.id, "added": saved["added"], "removed": saved["removed"].map(func(a): return a.id)}, 0)


func _revert_form(inst: StatusInstance, holder: CombatEntity) -> void:
	var saved := inst.form_applied
	if saved.is_empty():
		return
	for aid in saved["added"]:
		engine.remove_ability(holder, str(aid))
	for old in saved["removed"]:
		if holder.get_ability((old as AbilityDef).id) == null:
			engine.add_ability(holder, old, "form_revert")
	holder.ai = saved["ai"]
	engine.emit(EventTypes.REVERTED, inst.source_id, holder.id, {"form": inst.def.id}, 0)


# --- Efectos de estados (on_apply / on_expire / periodicos) ----------------------------------------------

func run_effects(effects: Array, source: CombatEntity, holder: CombatEntity, inst: StatusInstance, cause: int) -> void:
	var caster: CombatEntity = source if (source != null and source.alive) else holder
	var ctx := ActionContext.new()
	ctx.engine = engine
	ctx.actor = caster
	ctx.targets = [holder]
	ctx.cause_id = cause
	ctx.status = inst
	ActionResolver.run_effects(engine, ctx, effects)


# --- Tics por evento -------------------------------------------------------------------------------------

func _on_event(ev: CombatEvent, _eng: CombatEngine) -> void:
	if engine.is_aborted():
		return
	match ev.type:
		EventTypes.TURN_STARTED:
			var e := engine.get_entity(ev.source_id)
			if e != null:
				_turn_start(e, ev)
		EventTypes.TURN_ENDED:
			var e2 := engine.get_entity(ev.source_id)
			if e2 != null:
				_turn_end(e2, ev)
		EventTypes.ACTION_RESOLVED:
			_global_action(ev)
	_events_unit(ev)


func _turn_start(e: CombatEntity, ev: CombatEvent) -> void:
	# cooldowns y recargas: al inicio del turno del dueno (no avanzan si un estado los suspende)
	if not e.suspends_cooldowns():
		for aid in e.cooldowns.keys():
			var du: Duration = e.cooldowns[aid]
			if du.unit == "target_turns":
				du.remaining -= 1.0
				if du.remaining <= 0.0:
					e.cooldowns.erase(aid)
		AbilityRuntime.tick_charges(engine, e, "turn")
	# regeneracion de recursos
	var ids: Array = e.resources.keys()
	ids.sort()
	for rid in ids:
		var r: ResourceState = e.resources[rid]
		if r.regen_per_turn != 0.0 and e.alive:
			engine.change_resource(e, rid, r.regen_per_turn, "regen", ev.id)
	_periodic(e, "turn_start", ev)


func _turn_end(e: CombatEntity, ev: CombatEvent) -> void:
	_periodic(e, "turn_end", ev)
	for holder_e in engine.entities.duplicate():
		for st in (holder_e as CombatEntity).statuses.duplicate():
			var du: Duration = st.duration
			var counts := false
			if st.frozen:
				continue
			if du.unit == "target_turns" and st.holder_id == e.id:
				counts = true
			elif du.unit == "caster_turns" and st.source_id == e.id:
				counts = true
			if not counts:
				continue
			if du.skip_turn == ev.data.get("turn", -2):
				du.skip_turn = -1
				continue
			du.remaining -= 1.0
			if du.remaining <= 0.0:
				remove(st, "expired", ev.id)
	if e.lifespan != null and e.lifespan.unit == "target_turns" and e.alive:
		e.lifespan.remaining -= 1.0
		if e.lifespan.remaining <= 0.0:
			engine.despawn(e, "lifespan", ev.id)


func _periodic(e: CombatEntity, when: String, ev: CombatEvent) -> void:
	if not e.alive:
		return
	for st in e.statuses.duplicate():
		if not e.statuses.has(st) or st.frozen:
			continue
		for p in st.def.periodic:
			if str(p["on"]) == when:
				if _tick_depth >= 8:
					engine.abort("max_status_depth", "efectos periodicos anidados en exceso")
					return
				_tick_depth += 1
				var effs: Array = p["effects"]
				if st.inverted:
					effs = effs.map(func(x): return invert_effect(x))
				run_effects(effs, engine.get_entity(st.source_id), e, st, ev.id)
				_tick_depth -= 1
				if not e.alive or engine.is_aborted():
					return


func _global_action(ev: CombatEvent) -> void:
	for holder_e in engine.entities.duplicate():
		var h: CombatEntity = holder_e
		for st in h.statuses.duplicate():
			if st.duration.unit != "global_actions" or st.frozen:
				continue
			if st.duration.skip_cause == ev.cause_id:
				st.duration.skip_cause = -1
				continue
			st.duration.remaining -= 1.0
			if st.duration.remaining <= 0.0:
				remove(st, "expired", ev.id)
		for aid in h.cooldowns.keys():
			if h.suspends_cooldowns():
				break
			var du: Duration = h.cooldowns[aid]
			if du.unit == "global_actions":
				if du.skip_cause == ev.cause_id:
					du.skip_cause = -1
					continue
				du.remaining -= 1.0
				if du.remaining <= 0.0:
					h.cooldowns.erase(aid)
		if h.lifespan != null and h.lifespan.unit == "global_actions" and h.alive:
			h.lifespan.remaining -= 1.0
			if h.lifespan.remaining <= 0.0:
				engine.despawn(h, "lifespan", ev.id)
		AbilityRuntime.tick_charges(engine, h, "action")


func _events_unit(ev: CombatEvent) -> void:
	for holder_e in engine.entities.duplicate():
		var h: CombatEntity = holder_e
		for st in h.statuses.duplicate():
			var du: Duration = st.duration
			if du.unit == "events" and not st.frozen and du.event_type == ev.type and _filter_ok(du.event_filter, ev, h.id):
				du.remaining -= 1.0
				if du.remaining <= 0.0:
					remove(st, "expired", ev.id)
		for aid in h.cooldowns.keys():
			var cd: Duration = h.cooldowns[aid]
			if cd.unit == "events" and cd.event_type == ev.type and _filter_ok(cd.event_filter, ev, h.id):
				cd.remaining -= 1.0
				if cd.remaining <= 0.0:
					h.cooldowns.erase(aid)


static func _filter_ok(filter: Dictionary, ev: CombatEvent, owner_id: String) -> bool:
	for k in filter:
		var actual := ev.source_id if str(k) == "source" else ev.target_id
		var is_self := actual == owner_id
		if (str(filter[k]) == "self") != is_self:
			return false
	return true
