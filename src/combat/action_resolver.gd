class_name ActionResolver
extends RefCounted
## Resuelve una accion ya validada.
##
## Orden (provisional, ver docs/COMBAT_RULES.md):
##   1. ACTION_STARTED (PRE; los interceptores pueden interrumpirla)
##   2. se consume el hueco de accion (un intento cuenta aunque se interrumpa)
##   3. si no se interrumpio: se pagan los costes (politica "pagar al comprometer")
##   4. se resuelven los efectos en orden, cada uno via su operacion registrada
##   5. ACTION_RESOLVED
## La victoria/derrota NO se evalua aqui: el motor lo hace al terminar la accion.

static func resolve(engine: CombatEngine, turn: TurnState, actor: CombatEntity, ability: AbilityDef, targets: Array[CombatEntity], selected_event_id: int) -> void:
	var first_target: String = targets[0].id if not targets.is_empty() else ""
	var target_ids: Array = []
	for t in targets:
		target_ids.append(t.id)
	var started := engine.emit(EventTypes.ACTION_STARTED, actor.id, first_target, {
		"ability": ability.id, "action_type": ability.action_type_name(), "targets": target_ids,
	}, selected_event_id, CombatEvent.Phase.PRE)
	turn.consume(ability)
	if started.cancelled:
		engine.emit(EventTypes.ACTION_INTERRUPTED, actor.id, first_target, {"ability": ability.id, "by": started.cancelled_by}, started.id)
		return
	var prev_started := engine.current_action_started_id
	engine.current_action_started_id = started.id
	AbilityRuntime.commit(engine, actor, ability)
	actor.prev_action = actor.last_action
	actor.last_action = {"ability": ability.id, "targets": target_ids}

	var cost_ids: Array = ability.cost.keys()
	cost_ids.sort()
	for rid in cost_ids:
		engine.change_resource(actor, rid, -float(ability.cost[rid]), "cost", started.id)

	var ctx := ActionContext.new()
	ctx.engine = engine
	ctx.actor = actor
	ctx.ability = ability
	ctx.targets = targets
	ctx.cause_id = started.id
	if ability.cast_time > 0.0:
		engine.begin_channel(actor, ability, targets, ctx)
		engine.current_action_started_id = prev_started
		return
	run_effects(engine, ctx, ability.effects)
	if engine.is_aborted():
		engine.current_action_started_id = prev_started
		return
	engine.emit(EventTypes.ACTION_RESOLVED, actor.id, first_target, {"ability": ability.id}, started.id)
	engine.current_action_started_id = prev_started


## Ejecuta una lista de efectos sobre ctx.targets. Maneja `on` (targets|caster)
## y `chance` (una tirada por objetivo, flujo "proc", registrada como evento `proc`).
static func run_effects(engine: CombatEngine, ctx: ActionContext, effects: Array) -> void:
	for effect in effects:
		if engine.is_aborted():
			return
		var op: EffectOperation = engine.registry.get_operation(str(effect["type"]))
		if op == null:
			engine.abort("unknown_operation", "operacion desconocida '%s'" % str(effect["type"]))
			return
		var saved: Array[CombatEntity] = ctx.targets
		var pool: Array[CombatEntity] = saved
		var on := str(effect.get("on", "targets"))
		if on != "targets":
			pool = select_targets(engine, ctx.actor, on, saved)
		if effect.has("chance"):
			var chance: float = float(effect["chance"])
			var kept: Array[CombatEntity] = []
			for t in pool:
				var roll: float = engine.rng.stream("proc").next_float()
				var ok := roll < chance
				engine.emit(EventTypes.PROC, ctx.actor.id, t.id, {"effect": str(effect["type"]), "chance": chance, "roll": roll, "success": ok}, ctx.cause_id)
				if ok:
					kept.append(t)
			pool = kept
		ctx.targets = pool
		op.resolve(ctx, effect)
		ctx.targets = saved


## Resuelve una habilidad "gratis" (sin hueco, costes, cooldown ni restricciones):
## usada por repeat_action y copy_action. Provisional (D-045).
static func resolve_free(engine: CombatEngine, actor: CombatEntity, ability: AbilityDef, targets: Array[CombatEntity], cause_id: int, via: String) -> void:
	if engine.free_depth >= 3:
		engine.emit(EventTypes.LIMIT_REACHED, actor.id, "", {"limit": "max_free_depth", "ability": ability.id}, cause_id)
		return
	engine.free_depth += 1
	var ids: Array = []
	for t in targets:
		ids.append(t.id)
	var first: String = ids[0] if not ids.is_empty() else ""
	var started := engine.emit(EventTypes.ACTION_STARTED, actor.id, first, {
		"ability": ability.id, "action_type": "free_copy", "targets": ids, "via": via,
	}, cause_id, CombatEvent.Phase.PRE)
	if started.cancelled:
		engine.emit(EventTypes.ACTION_INTERRUPTED, actor.id, first, {"ability": ability.id, "by": started.cancelled_by}, started.id)
		engine.free_depth -= 1
		return
	var prev := engine.current_action_started_id
	engine.current_action_started_id = started.id
	var ctx := ActionContext.new()
	ctx.engine = engine
	ctx.actor = actor
	ctx.ability = ability
	ctx.targets = targets
	ctx.cause_id = started.id
	run_effects(engine, ctx, ability.effects)
	if not engine.is_aborted():
		engine.emit(EventTypes.ACTION_RESOLVED, actor.id, first, {"ability": ability.id}, started.id)
	engine.current_action_started_id = prev
	engine.free_depth -= 1


## Selectores de objetivo de una operacion (`on`). Deterministas: orden por `slot` y azar
## solo del flujo "select". "targets" = objetivos de la accion; "caster"; "all_enemies";
## "all_allies" (sin el lanzador); "random_enemy"/"random_ally"; "lowest_hp_enemy".
static func select_targets(engine: CombatEngine, actor: CombatEntity, selector: String, action_targets: Array[CombatEntity]) -> Array[CombatEntity]:
	var out: Array[CombatEntity] = []
	match selector:
		"targets":
			return action_targets
		"caster":
			out.append(actor)
		"all_enemies", "random_enemy", "lowest_hp_enemy", "all_allies", "random_ally":
			var want := "enemy" if selector.ends_with("enemy") or selector == "all_enemies" else "ally"
			var pool: Array[CombatEntity] = []
			for e in engine.entities:
				if e.alive and engine.relation(actor, e) == want:
					pool.append(e)
			if selector.begins_with("random") and not pool.is_empty():
				out.append(pool[engine.rng.stream("select").next_int(pool.size())])
			elif selector == "lowest_hp_enemy" and not pool.is_empty():
				var best := pool[0]
				for e in pool:
					if e.hp < best.hp:
						best = e
				out.append(best)
			elif selector.begins_with("all"):
				out = pool
	return out
