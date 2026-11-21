class_name AIFactory
extends RefCounted
## Construye una IA a partir de su configuracion declarativa.
## {"type": "passive"} | {"type": "priority_list", ...} | {"type": "scored", ...} |
## {"type": "state_machine", ...} | {"type": "behavior_tree", ...} | {"type": "script", ...}. Todas admiten "reactions" (AIReactionPolicy).

const TYPES := ["passive", "priority_list", "scored", "state_machine", "behavior_tree", "script"]

## Devuelve {"ai": AIController|null, "errors": Array}.
static func build(cfg: Variant) -> Dictionary:
	if not (cfg is Dictionary):
		return {"ai": null, "errors": ["ia: se esperaba un objeto"]}
	var errs: Array = []
	var ai: AIController = null
	match str(cfg.get("type", "")):
		"passive":
			for k in cfg:
				if not ["type", "reactions"].has(str(k)):
					errs.append("ia passive: propiedad desconocida '%s'" % str(k))
			ai = PassiveAI.new()
		"priority_list":
			for k in cfg:
				if not ["type", "rules", "reactions"].has(str(k)):
					errs.append("ia priority_list: propiedad desconocida '%s'" % str(k))
			errs.append_array(PriorityListAI.validate(cfg))
			if errs.is_empty():
				ai = PriorityListAI.from_dict(cfg)
		"scored":
			errs.append_array(ScoredAI.validate(cfg))
			if errs.is_empty():
				ai = ScoredAI.from_dict(cfg)
		"state_machine":
			errs.append_array(StateMachineAI.validate(cfg))
			if errs.is_empty():
				ai = StateMachineAI.from_dict(cfg)
		"script":
			errs.append_array(ScriptAI.validate(cfg))
			if errs.is_empty():
				ai = ScriptAI.from_dict(cfg)
		"behavior_tree":
			errs.append_array(BehaviorTreeAI.validate(cfg))
			if errs.is_empty():
				ai = BehaviorTreeAI.from_dict(cfg)
		_:
			return {"ai": null, "errors": ["ia: tipo desconocido '%s' (use: %s)" % [str(cfg.get("type", "")), ", ".join(TYPES)]]}
	if cfg.has("reactions"):
		errs.append_array(AIReactionPolicy.validate(cfg["reactions"]))
	if not errs.is_empty():
		return {"ai": null, "errors": errs}
	if cfg.has("reactions"):
		ai.reaction_policy = AIReactionPolicy.from_dict(cfg["reactions"])
	return {"ai": ai, "errors": []}


## IA por defecto del ataque basico universal: ataca al enemigo con menos vida.
static func default_attacker(basic_attack_id: String) -> AIController:
	return PriorityListAI.from_dict({"rules": [{"ability": basic_attack_id, "target": "lowest_hp_enemy"}]})
