class_name TriggerService
extends RefCounted
## Habilidades disparadas por eventos: reacciones (fuera de turno), automaticas y
## pasivas con efecto. Una habilidad con `trigger` NO es seleccionable por la IA.
##
## trigger: {"event": "damage_dealt", "when": {"event.target": {"eq": "self"}, "event.crit": {"eq": true}},
##           "target": "event_source|event_target|self|lowest_hp_enemy|first_enemy" (por defecto: self si la
##           habilidad es de objetivo propio; si no, event_source),
##           "chance": 0.5, "while_dead": false, "limit_per_turn": 1}
## Orden: las suscripciones se ejecutan por prioridad y orden de alta (estable).
## Los eventos PRE cancelados no disparan reacciones. Limites tecnicos: cadena de
## reacciones (safety.max_reaction_chain) y profundidad de eventos.
## La reaccion paga costes y respeta cooldown/usos/cargas como cualquier accion.

var engine: CombatEngine


func _init(eng: CombatEngine) -> void:
	engine = eng


static func owner_key(entity: CombatEntity, ability_id: String) -> String:
	return "trig:%s:%s" % [entity.id, ability_id]


func register(entity: CombatEntity, ability: AbilityDef) -> void:
	var eid := entity.id
	var aid := ability.id
	engine.dispatcher.observe(str(ability.trigger["event"]), func(ev: CombatEvent, _g: CombatEngine): _on_event(ev, eid, aid), 0, owner_key(entity, ability.id))


func unregister(entity: CombatEntity, ability_id: String) -> void:
	engine.dispatcher.unsubscribe_owner(owner_key(entity, ability_id))


func _on_event(ev: CombatEvent, entity_id: String, ability_id: String) -> void:
	if ev.cancelled or engine.is_aborted():
		return
	var e := engine.get_entity(entity_id)
	if e == null:
		return
	var ab := e.get_ability(ability_id)
	if ab == null:
		return
	var trig: Dictionary = ab.trigger
	if not e.alive and not bool(trig.get("while_dead", false)):
		return
	if trig.has("when") and not ConditionEvaluator.holds(engine, trig["when"], e, null, ev):
		return
	if AbilityRuntime.blocked_reason(engine, e, ab) != "" or not ActionValidator.can_pay(e, ab):
		return
	var s := AbilityRuntime.state(e, ab)
	if trig.has("limit_per_turn"):
		if int(s.get("trig_turn", -1)) == engine.turn_count and int(s.get("trig_uses", 0)) >= int(trig["limit_per_turn"]):
			return
	var default_target := "self" if ab.targeting == "self" else "event_source"
	var target := _pick_target(e, ev, str(trig.get("target", default_target)))
	if target == null:
		return
	if not ab.requires.is_empty() and not AbilityRuntime.target_ok(engine, e, ab, target):
		return
	if engine.reaction_depth >= engine.rules.max_reaction_chain():
		engine.emit(EventTypes.LIMIT_REACHED, e.id, "", {"limit": "max_reaction_chain", "ability": ab.id}, ev.id)
		return
	if ab.action_type == AbilityDef.ActionType.REACTION and e.ai != null and e.ai.has_reaction_policy():
		var req := {"ability_id": ab.id, "target_id": target.id, "event": {
			"type": ev.type, "source": ev.source_id, "target": ev.target_id, "amount": float(ev.data.get("amount", 0.0))}}
		var verdict: Dictionary = e.ai.decide_reaction(ViewBuilder.build_for_reaction(engine, e), req)
		if not bool(verdict["allow"]):
			engine.emit(EventTypes.REACTION_DECLINED, e.id, target.id, {"ability": ab.id, "event": ev.type, "event_id": ev.id, "reason": str(verdict["reason"])}, ev.id)
			return
	if trig.has("chance"):
		var chance: float = float(trig["chance"])
		var roll: float = engine.rng.stream("proc").next_float()
		engine.emit(EventTypes.PROC, e.id, target.id, {"effect": "trigger:" + ab.id, "chance": chance, "roll": roll, "success": roll < chance}, ev.id)
		if roll >= chance:
			return
	if int(s.get("trig_turn", -1)) != engine.turn_count:
		s["trig_turn"] = engine.turn_count
		s["trig_uses"] = 0
	s["trig_uses"] = int(s["trig_uses"]) + 1
	var trig_ev := engine.emit(EventTypes.REACTION_TRIGGERED, e.id, target.id, {"ability": ab.id, "event": ev.type, "event_id": ev.id}, ev.id)
	engine.reaction_depth += 1
	var targets: Array[CombatEntity] = [target]
	ActionResolver.resolve(engine, TurnState.new(e, engine.turn_count), e, ab, targets, trig_ev.id)
	engine.reaction_depth -= 1


func _pick_target(e: CombatEntity, ev: CombatEvent, selector: String) -> CombatEntity:
	var t: CombatEntity = null
	match selector:
		"self":
			t = e
		"event_source":
			t = engine.get_entity(ev.source_id)
		"event_target":
			t = engine.get_entity(ev.target_id)
		"random_enemy":
			var pool: Array[CombatEntity] = []
			for o in engine.entities:
				if o.alive and engine.relation(e, o) == "enemy":
					pool.append(o)
			if not pool.is_empty():
				t = pool[engine.rng.stream("select").next_int(pool.size())]
		"lowest_hp_enemy", "first_enemy":
			var best: CombatEntity = null
			for o in engine.entities:
				if o.alive and engine.relation(e, o) == "enemy":
					if best == null or (selector == "lowest_hp_enemy" and o.hp < best.hp):
						best = o
			t = best
	if t == null or (not t.alive and selector != "self"):
		return null
	return t
