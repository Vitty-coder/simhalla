class_name AbilityRuntime
extends RefCounted
## Estado de ejecucion de las habilidades de una entidad y restricciones de uso:
## cooldown, usos por combate/turno, cargas con recarga, condiciones (`requires`),
## bloqueos por estados (silencio, etc.).
##
## Politica (provisional, D-016/D-040): el coste, el cooldown y el consumo de usos
## y cargas se aplican AL COMPROMETER la accion (tras los interceptores de
## action_started). Una accion interrumpida antes de comprometerse no los gasta.
## "Por turno" se mide por turno global (los usos de una reaccion cuentan contra
## el turno en curso).

static func state(entity: CombatEntity, ability: AbilityDef) -> Dictionary:
	if not entity.ability_state.has(ability.id):
		var st := {"uses_combat": 0, "uses_turn": 0, "turn": -1, "charges": 0, "recharge": null}
		if not ability.charges.is_empty():
			st["charges"] = int(ability.charges.get("initial", ability.charges["max"]))
		entity.ability_state[ability.id] = st
	return entity.ability_state[ability.id]


## Motivo por el que la habilidad no se puede usar AHORA (sin considerar objetivo), o "".
static func blocked_reason(engine: CombatEngine, entity: CombatEntity, ability: AbilityDef) -> String:
	for st in entity.statuses:
		if st.frozen:
			continue
		for tag in st.def.flags.get("block_tags", []):
			if ability.tags.has(str(tag)):
				return "bloqueada:%s" % st.def.id
		for at in st.def.flags.get("block_action_types", []):
			if str(at) == ability.action_type_name():
				return "bloqueada:%s" % st.def.id
	var s := state(entity, ability)
	_catch_up_time(engine, entity, ability, s)
	if entity.cooldowns.has(ability.id):
		var du: Duration = entity.cooldowns[ability.id]
		if du.unit == "time" and engine.scheduler.now >= du.expires_at:
			entity.cooldowns.erase(ability.id)
		else:
			return "cooldown"
	if ability.uses_per_combat > 0 and int(s["uses_combat"]) >= ability.uses_per_combat:
		return "usos_por_combate"
	if ability.uses_per_turn > 0 and int(s["turn"]) == engine.turn_count and int(s["uses_turn"]) >= ability.uses_per_turn:
		return "usos_por_turno"
	if not ability.charges.is_empty() and int(s["charges"]) <= 0:
		return "sin_cargas"
	if not ability.requires.is_empty():
		var self_only := {}
		for k in ability.requires:
			if str(k).begins_with("self."):
				self_only[k] = ability.requires[k]
		if not ConditionEvaluator.holds(engine, self_only, entity, null, null):
			return "requisito"
	return ""


## Condiciones sobre el objetivo (target.*) de `requires`.
static func target_ok(engine: CombatEngine, entity: CombatEntity, ability: AbilityDef, target: CombatEntity) -> bool:
	var tconds := {}
	for k in ability.requires:
		if str(k).begins_with("target."):
			tconds[k] = ability.requires[k]
	return tconds.is_empty() or ConditionEvaluator.holds(engine, tconds, entity, target, null)


static func commit(engine: CombatEngine, entity: CombatEntity, ability: AbilityDef) -> void:
	var s := state(entity, ability)
	s["uses_combat"] = int(s["uses_combat"]) + 1
	if int(s["turn"]) != engine.turn_count:
		s["turn"] = engine.turn_count
		s["uses_turn"] = 0
	s["uses_turn"] = int(s["uses_turn"]) + 1
	if not ability.charges.is_empty():
		s["charges"] = int(s["charges"]) - 1
		if s["recharge"] == null and ability.charges.has("recharge") and int(s["charges"]) < int(ability.charges["max"]):
			_start_recharge(engine, ability, s)
	if ability.cooldown != null:
		var du := Duration.from_dict(ability.cooldown)
		if du.unit == "time":
			du.expires_at = engine.scheduler.now + int(round(du.amount * Ruleset.TIME_SCALE))
		elif du.unit == "global_actions":
			du.skip_cause = engine.current_action_started_id
		entity.cooldowns[ability.id] = du


static func _start_recharge(engine: CombatEngine, ability: AbilityDef, s: Dictionary) -> void:
	var du := Duration.from_dict(ability.charges["recharge"])
	if du.unit == "time":
		du.expires_at = engine.scheduler.now + int(round(du.amount * Ruleset.TIME_SCALE))
	s["recharge"] = du


static func _catch_up_time(engine: CombatEngine, entity: CombatEntity, ability: AbilityDef, s: Dictionary) -> void:
	var du: Duration = s["recharge"]
	if du == null or du.unit != "time":
		return
	var cap := int(ability.charges.get("max", 0))
	while du != null and engine.scheduler.now >= du.expires_at:
		s["charges"] = int(s["charges"]) + 1
		if int(s["charges"]) >= cap:
			s["recharge"] = null
			du = null
		else:
			du.expires_at += int(round(du.amount * Ruleset.TIME_SCALE))


## kind: "turn" (inicio de turno del dueno) | "action" (accion global resuelta).
static func tick_charges(engine: CombatEngine, entity: CombatEntity, kind: String) -> void:
	for ability in entity.abilities:
		if ability.charges.is_empty():
			continue
		var s := state(entity, ability)
		var du: Duration = s["recharge"]
		if du == null:
			continue
		if (kind == "turn" and du.unit == "target_turns") or (kind == "action" and du.unit == "global_actions"):
			du.remaining -= 1.0
			if du.remaining <= 0.0:
				s["charges"] = mini(int(s["charges"]) + 1, int(ability.charges["max"]))
				s["recharge"] = null
				if int(s["charges"]) < int(ability.charges["max"]):
					_start_recharge(engine, ability, s)
