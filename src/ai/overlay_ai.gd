class_name OverlayAI
extends AIController
## Reglas de IA del artefacto (`artifact.ai_rules`) antepuestas a una IA que no es una
## lista de prioridades (scored, state_machine, behavior_tree): si alguna regla del
## artefacto se aplica gana (razon `artifact_rule_N`); si no, decide la IA base.
## La politica de reacciones y la memoria son las de la IA base.

var head: PriorityListAI
var inner: AIController


static func wrap(base: AIController, rules: Array) -> OverlayAI:
	var o := OverlayAI.new()
	o.head = PriorityListAI.from_dict({"rules": rules})
	o.inner = base
	return o


func ai_id() -> String:
	return "overlay(%s)" % inner.ai_id()


func wants_memory() -> bool:
	return true


func referenced_abilities() -> Array:
	return head.referenced_abilities() + inner.referenced_abilities()


func bind_scripts(scripts: Dictionary, lim: ScriptLimits) -> Array:
	return inner.bind_scripts(scripts, lim)


func has_reaction_policy() -> bool:
	return inner.has_reaction_policy()


func decide_reaction(view: Dictionary, req: Dictionary) -> Dictionary:
	return inner.decide_reaction(view, req)


func decide(view: Dictionary) -> AIDecision:
	var d := head.decide(view)
	if d.kind == AIDecision.Kind.ABILITY:
		d.reason = "artifact_" + d.reason
		return d
	var base := inner.decide(view)
	base.details["artifact_rules_discarded"] = d.details.get("discarded", [])
	return base
