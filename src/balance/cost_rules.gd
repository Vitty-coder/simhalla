class_name CostRules
extends RefCounted
## Reglas de coste declaradas por un perfil de equilibrio (JSON externo y versionado).
##
## Cada regla es una FORMULA de la gramatica segura (`Formula`: + - * / % ^, min, max, clamp, abs,
## floor, ceil, round, sqrt; sin `eval`) sobre HECHOS nombrados que calcula el evaluador a partir
## del contenido. El perfil decide los numeros; el motor no incrusta ningun coste. Un hecho no
## declarado en las tablas de abajo es un error al cargar el perfil.
##
## Estructura del bloque `costs` del perfil:
##   stats       {credit_factor, default:{formula}, rules:{STAT:{formula}}, patterns:{"ELEM_RES.*":{formula}}, custom:{formula}}
##   operations  {<tipo de operacion>: {formula}}        (las no listadas ni gratuitas = NO evaluables)
##   ability     {formula, min}
##   resource    {formula}
##   status_def  {formula}
##   weaknesses  {self_damage:{formula}}                  (credito por dano autoinfligido)
##   free        {basic_attack: true, ai: true, operations:[...]}   (ataque basico e IA: SIEMPRE gratuitos)

const STAT_FACTS := ["delta", "base", "value"]
const COMMON_OP_FACTS := ["chance", "targets", "on_caster"]
## Hechos propios de cada operacion (ademas de COMMON_OP_FACTS).
const OP_FACTS := {
	"damage": ["power", "components", "pen_pct", "pen_flat", "elem_pen", "always_hit", "can_crit", "crit_bonus", "true_share"],
	"heal": ["power", "can_crit"],
	"apply_status": ["stacks", "duration", "magnitude"],
	"remove_status": ["count", "force", "by_tags"],
	"extend_status": ["amount"],
	"transfer_status": ["count", "steal", "give"],
	"invert_status": ["count"],
	"propagate_status": ["count"],
	"modify_resource": ["amount", "is_max", "is_set"],
	"modify_initiative": ["amount", "extra_turn", "steal"],
	"modify_cooldown": ["amount", "reset", "all"],
	"summon": ["count", "lifespan", "template_cost", "inherit_pct"],
	"record_state": ["what_count"],
	"restore_state": ["what_count", "consume"],
	"delayed_effect": ["delay", "inner"],
	"repeat_action": ["times"],
	"copy_action": [],
}
const ABILITY_FACTS := ["effects", "has_effects", "cooldown", "resource_cost", "resource_cost_ratio", "limited", "uses_per_combat",
	"uses_per_turn", "charges", "cast_time", "requires", "is_free", "is_reaction", "is_triggered", "trigger_chance", "trigger_limit", "target_count"]
const RESOURCE_FACTS := ["initial", "max", "min", "regen"]
const STATUS_FACTS := ["inner", "modifiers", "flags", "defense", "periodic", "has_form", "max_stacks", "beneficial"]
const WEAKNESS_FACTS := ["power"]
const FREE_KEYS := ["basic_attack", "ai", "operations"]
const SECTIONS := ["stats", "operations", "ability", "resource", "status_def", "weaknesses", "free"]
const STAT_KEYS := ["credit_factor", "default", "rules", "patterns", "custom"]


static func op_facts(op: String) -> Array:
	return COMMON_OP_FACTS + OP_FACTS.get(op, [])


## Valida el bloque `costs`. Devuelve errores con la ruta de la propiedad.
static func validate(costs: Variant) -> Array:
	var errs: Array = []
	if not (costs is Dictionary):
		return ["costs debe ser un objeto"]
	for k in costs:
		if not SECTIONS.has(str(k)):
			errs.append("costs: seccion desconocida '%s' (use: %s)" % [str(k), ", ".join(SECTIONS)])
	var st: Variant = costs.get("stats", {})
	if st is Dictionary:
		for k in st:
			if not STAT_KEYS.has(str(k)):
				errs.append("costs.stats: propiedad desconocida '%s'" % str(k))
		if st.has("credit_factor") and (not (st["credit_factor"] is float or st["credit_factor"] is int) or float(st["credit_factor"]) < 0.0 or float(st["credit_factor"]) > 1.0):
			errs.append("costs.stats.credit_factor debe estar entre 0 y 1")
		for k in ["default", "custom"]:
			if st.has(k):
				errs.append_array(_check_rule(st[k], "costs.stats." + k, STAT_FACTS))
		for group in ["rules", "patterns"]:
			if st.has(group):
				if not (st[group] is Dictionary):
					errs.append("costs.stats.%s debe ser un objeto" % group)
				else:
					for key in st[group]:
						errs.append_array(_check_rule(st[group][key], "costs.stats.%s.%s" % [group, str(key)], STAT_FACTS))
						if group == "patterns" and not (str(key).ends_with("*") and str(key).length() > 1):
							errs.append("costs.stats.patterns.%s: el patron debe terminar en '*' (p. ej. ELEM_RES.*)" % str(key))
	else:
		errs.append("costs.stats debe ser un objeto")
	var ops: Variant = costs.get("operations", {})
	if ops is Dictionary:
		for op in ops:
			if not OP_FACTS.has(str(op)):
				errs.append("costs.operations: operacion sin modelo de coste '%s' (use: %s)" % [str(op), ", ".join(OP_FACTS.keys())])
			else:
				errs.append_array(_check_rule(ops[op], "costs.operations." + str(op), op_facts(str(op))))
	else:
		errs.append("costs.operations debe ser un objeto")
	for pair in [["ability", ABILITY_FACTS], ["resource", RESOURCE_FACTS], ["status_def", STATUS_FACTS]]:
		if costs.has(pair[0]):
			errs.append_array(_check_rule(costs[pair[0]], "costs." + pair[0], pair[1], ["min"] if pair[0] == "ability" else []))
	if costs.has("ability") and costs["ability"] is Dictionary:
		var mn: Variant = costs["ability"].get("min", 0.0)
		if not (mn is float or mn is int):
			errs.append("costs.ability.min debe ser numerico")
	var wk: Variant = costs.get("weaknesses", {})
	if wk is Dictionary:
		for k in wk:
			if str(k) != "self_damage":
				errs.append("costs.weaknesses: propiedad desconocida '%s'" % str(k))
			else:
				errs.append_array(_check_rule(wk[k], "costs.weaknesses.self_damage", WEAKNESS_FACTS))
	else:
		errs.append("costs.weaknesses debe ser un objeto")
	var fr: Variant = costs.get("free", {})
	if fr is Dictionary:
		for k in fr:
			if not FREE_KEYS.has(str(k)):
				errs.append("costs.free: propiedad desconocida '%s'" % str(k))
		# PROJECT.md §9.1: la IA y el ataque basico universal son gratuitos (no negociable por perfil)
		if fr.has("ai") and fr["ai"] != true:
			errs.append("costs.free.ai debe ser true: la IA de comportamiento es gratuita (PROJECT.md 9.1)")
		if fr.has("basic_attack") and fr["basic_attack"] != true:
			errs.append("costs.free.basic_attack debe ser true: el ataque basico universal es gratuito (PROJECT.md 9.1)")
		var fo: Variant = fr.get("operations", [])
		if not (fo is Array):
			errs.append("costs.free.operations debe ser una lista")
		else:
			for o in fo:
				if not OP_FACTS.has(str(o)) and not ["emit_event", "metric"].has(str(o)):
					errs.append("costs.free.operations: operacion desconocida '%s'" % str(o))
	else:
		errs.append("costs.free debe ser un objeto")
	return errs


static func _check_rule(rule: Variant, where: String, facts: Array, extra_keys: Array = []) -> Array:
	if not (rule is Dictionary) or not (rule.get("formula", null) is String):
		return ["%s: debe ser {\"formula\": \"...\"}" % where]
	for k in rule:
		if str(k) != "formula" and str(k) != "note" and not extra_keys.has(str(k)):
			return ["%s: propiedad desconocida '%s'" % [where, str(k)]]
	var f := Formula.parse(str(rule["formula"]))
	if not f.is_valid():
		return ["%s.formula: %s" % [where, f.error]]
	var errs: Array = []
	for p in f.referenced_paths():
		if not facts.has(str(p)):
			errs.append("%s.formula: hecho no disponible '%s' (use: %s)" % [where, str(p), ", ".join(facts)])
	return errs


## Evalua la formula de una regla con los hechos dados: {"ok", "value", "error"}.
static func evaluate(rule: Dictionary, facts: Dictionary) -> Dictionary:
	var f := Formula.parse(str(rule["formula"]))
	return f.evaluate(func(parts: Array) -> Dictionary:
		var key := ".".join(parts)
		if facts.has(key):
			return {"ok": true, "value": float(facts[key]), "error": ""}
		return {"ok": false, "value": 0.0, "error": "hecho no disponible '%s'" % key})
