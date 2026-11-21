class_name ActionValidator
extends RefCounted
## Validacion de acciones propuestas: el motor revalida SIEMPRE a la IA.
##
## Comprueba: la entidad vive, posee la habilidad, hay hueco de accion (principal
## o gratuita; las reacciones solo fuera de turno propio), puede pagar el coste y
## los objetivos son validos segun `targeting`. Cooldowns, usos y cargas: fase 3.

static func slot_available(engine: CombatEngine, turn: TurnState, ability: AbilityDef) -> bool:
	match ability.action_type:
		AbilityDef.ActionType.MAIN:
			return turn.main_used < engine.rules.main_actions_per_turn()
		AbilityDef.ActionType.FREE:
			return true
		_:
			return false # REACTION: no se elige durante el turno propio


static func can_pay(entity: CombatEntity, ability: AbilityDef) -> bool:
	for rid in ability.cost:
		var r: ResourceState = entity.get_resource(rid)
		if r == null or r.value < float(ability.cost[rid]):
			return false
	return true


static func valid_targets(engine: CombatEngine, entity: CombatEntity, ability: AbilityDef) -> Array:
	var out: Array = []
	var taunters: Array = []
	if ability.targeting == "enemy" and not ability.ignore_taunt:
		for e in engine.entities:
			var o: CombatEntity = e
			if o.alive and engine.relation(entity, o) == "enemy" and o.has_status_flag("taunt"):
				taunters.append(o.id)
	for e in engine.entities:
		var o: CombatEntity = e
		if not o.alive:
			continue
		var rel := engine.relation(entity, o)
		match ability.targeting:
			"enemy":
				if rel == "enemy" and (taunters.is_empty() or taunters.has(o.id)):
					out.append(o.id)
			"ally":
				if rel == "ally":
					out.append(o.id)
			"self":
				if rel == "self":
					out.append(o.id)
			"any":
				out.append(o.id)
	if not ability.requires.is_empty():
		out = out.filter(func(id): return AbilityRuntime.target_ok(engine, entity, ability, engine.get_entity(id)))
	return out


static func legal_actions(engine: CombatEngine, entity: CombatEntity, turn: TurnState) -> Array:
	var out: Array = []
	if not entity.alive:
		return out
	for a in engine.available_abilities(entity):
		if a.is_triggered() or not slot_available(engine, turn, a) or not can_pay(entity, a):
			continue
		if AbilityRuntime.blocked_reason(engine, entity, a) != "":
			continue
		var targets := valid_targets(engine, entity, a)
		if targets.is_empty():
			continue
		out.append({"ability_id": a.id, "action_type": a.action_type_name(), "targets": targets})
	return out


## Devuelve "" si es valida, o el motivo del rechazo.
static func validate(engine: CombatEngine, entity: CombatEntity, turn: TurnState, decision: AIDecision) -> String:
	if not entity.alive:
		return "actor_muerto"
	var ability := entity.get_ability(decision.ability_id)
	if ability == null:
		return "habilidad_inexistente:%s" % decision.ability_id
	if not engine.available_abilities(entity).has(ability):
		return "habilidad_no_disponible:%s" % ability.id
	if ability.is_triggered():
		return "solo_reactiva:%s" % ability.id
	if not slot_available(engine, turn, ability):
		return "sin_hueco_de_accion:%s" % ability.action_type_name()
	var blocked := AbilityRuntime.blocked_reason(engine, entity, ability)
	if blocked != "":
		return "no_disponible:%s" % blocked
	if not can_pay(entity, ability):
		return "coste_no_pagable"
	if decision.target_ids.is_empty():
		return "sin_objetivos"
	if decision.target_ids.size() > ability.target_count:
		return "demasiados_objetivos"
	var valid := valid_targets(engine, entity, ability)
	var seen := {}
	for t in decision.target_ids:
		if seen.has(t):
			return "objetivo_duplicado:%s" % t
		seen[t] = true
		if not valid.has(t):
			return "objetivo_invalido:%s" % t
	return ""
