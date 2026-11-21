class_name ViewBuilder
extends RefCounted
## Construye la vista de SOLO LECTURA que recibe la IA.
##
## Propias: estado completo. Resto de entidades: solo los campos configurados en
## `ai.visible_fields` (por defecto hp, hp_max, initiative, resources, statuses).
## Nunca se exponen estadisticas del rival, habilidades, cooldowns, memoria ni
## variables internas. Todo es copia: la IA no puede mutar el estado real.

## Vista para decidir una reaccion fuera de turno: sin acciones legales ni hueco de turno.
static func build_for_reaction(engine: CombatEngine, entity: CombatEntity) -> Dictionary:
	return build(engine, entity, null)


static func build(engine: CombatEngine, entity: CombatEntity, turn: TurnState) -> Dictionary:
	var visible: Array = engine.rules.get_path_value("ai.visible_fields")
	var scale := float(Ruleset.TIME_SCALE)
	var abilities: Array = []
	var with_profile: bool = entity.ai != null and entity.ai.wants_memory() # estimaciones: solo si la IA las usa
	for a in engine.available_abilities(entity):
		abilities.append({"id": a.id, "action_type": a.action_type_name(), "cost": a.cost.duplicate(),
			"targeting": a.targeting, "tags": a.tags.duplicate(), "profile": _profile(engine, entity, a) if with_profile else {}})
	var res := {}
	for rid in entity.resources:
		res[rid] = (entity.resources[rid] as ResourceState).value
	var me := {
		"id": entity.id, "team": entity.team, "hp": entity.hp, "hp_max": entity.hp_max(),
		"hp_ratio": entity.hp_ratio(), "initiative": float(entity.initiative_micro) / scale,
		"resources": res, "stats": entity.stats.effective_map(), "abilities": abilities,
		"tags": entity.tags.duplicate(), "memory": entity.ai_memory.duplicate(true),
		"statuses": entity.statuses.map(func(st): return {"id": st.def.id, "stacks": st.stacks, "tags": st.def.tags.duplicate()}),
		"cooldowns": entity.cooldowns.keys(),
	}
	var others: Array = []
	for e in engine.entities:
		var o: CombatEntity = e
		if o == entity:
			continue
		var d := {"id": o.id, "team": o.team, "alive": o.alive, "relation": engine.relation(entity, o)}
		if visible.has("hp"):
			d["hp"] = o.hp
		if visible.has("hp_max"):
			d["hp_max"] = o.hp_max()
		if visible.has("initiative"):
			d["initiative"] = float(o.initiative_micro) / scale
		if visible.has("resources"):
			var r := {}
			for rid in o.resources:
				r[rid] = (o.resources[rid] as ResourceState).value
			d["resources"] = r
		if visible.has("statuses"):
			d["statuses"] = o.statuses.map(func(st): return {"id": st.def.id, "stacks": st.stacks, "tags": st.def.tags.duplicate()})
		others.append(d)
	return {
		"atb_threshold": float(engine.scheduler.threshold) / scale,
		"time": float(engine.scheduler.now) / scale,
		"turn": engine.turn_count,
		"self": me,
		"others": others,
		"legal_actions": ActionValidator.legal_actions(engine, entity, turn) if turn != null else [],
		"turn_state": {
			"main_remaining": maxi(engine.rules.main_actions_per_turn() - turn.main_used, 0) if turn != null else 0,
			"actions_taken": turn.actions_taken if turn != null else 0,
		},
	}


## Conocimiento PROPIO de una habilidad (efectos evaluados solo con las estadisticas del
## lanzador): sin objetivo no se resuelven formulas con `target.*` (valor null =
## desconocido). Resumen para estimaciones; no incluye informacion del rival.
static func _profile(engine: CombatEngine, entity: CombatEntity, ab: AbilityDef) -> Dictionary:
	var damage: Array = []
	var heals: Array = []
	var statuses: Array = []
	var other := false
	var fctx := FormulaContext.new(entity, null)
	for eff in ab.effects:
		match str(eff.get("type", "")):
			"damage":
				for c in eff["components"]:
					damage.append({
						"base": _eval(engine, str(c["formula"]), fctx), "damage_type": str(c["damage_type"]),
						"element": str(c.get("element", "")), "always_hit": bool(eff.get("always_hit", false)),
						"can_crit": bool(eff.get("can_crit", true)), "crit_bonus": float(eff.get("crit_bonus", 0.0)),
					})
			"heal":
				heals.append({"base": _eval(engine, str(eff["formula"]), fctx), "can_crit": bool(eff.get("can_crit", false))})
			"apply_status":
				if str(eff.get("on", "targets")) != "caster":
					statuses.append(str(eff["status"]))
				else:
					other = true
			_:
				other = true
	return {"damage": damage, "heals": heals, "statuses": statuses, "other": other, "cast_time": ab.cast_time}


static func _eval(engine: CombatEngine, formula: String, fctx: FormulaContext) -> Variant:
	var r := engine.eval_formula(formula, fctx)
	return float(r["value"]) if bool(r["ok"]) else null
