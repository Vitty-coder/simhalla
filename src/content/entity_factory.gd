class_name EntityFactory
extends RefCounted
## Construye una CombatEntity a partir de datos declarativos (diccionario/JSON).
##
## Es el embrion de la importacion de la fase 2 (paquetes multi-archivo con
## manifiesto, versiones y dependencias): aqui se valida una entidad ya
## cargada. No ejecuta codigo; solo datos. Los costes de creacion (PC) no se
## evaluan todavia (fase 6): se informa en `warnings`.
##
## Formato (ver docs/DATA_SCHEMAS.md):
## {"id","name","team","tags":[],"stats":{"ATK":150},
##  "resources":{"mana":{"initial":50,"max":100,"min":0}},
##  "basic_attack":true,"abilities":[...],"ai":{...}}

const ALLOWED_KEYS := ["id", "name", "team", "tags", "stats", "resources", "basic_attack", "abilities", "ai", "counts_for_victory",
	"artifact", "statuses", "summons", "scripts"]
const ARTIFACT_KEYS := ["id", "name", "modifiers", "abilities", "resources", "statuses", "summons", "ai_rules"]
const MODIFIER_KEYS := ["stat", "kind", "value", "priority"]

## Devuelve {"entity": CombatEntity|null, "errors": Array, "warnings": Array}.
static func build(data: Dictionary, profile: BalanceProfile, rules: Ruleset, registry: OperationRegistry, overrides: Dictionary = {}) -> Dictionary:
	var errs: Array = []
	var warns: Array = []
	var d: Dictionary = data.duplicate(true)
	for k in overrides:
		d[k] = overrides[k]

	for k in d:
		if not ALLOWED_KEYS.has(str(k)):
			errs.append("propiedad desconocida '%s' (permitidas: %s)" % [str(k), ", ".join(ALLOWED_KEYS)])

	var e := CombatEntity.new()
	e.id = str(d.get("id", ""))
	if e.id == "":
		errs.append("entidad sin 'id'")
	e.display_name = str(d.get("name", e.id))
	e.team = str(d.get("team", ""))
	for t in d.get("tags", []):
		e.tags.append(str(t))
	e.counts_for_victory = bool(d.get("counts_for_victory", true))

	profile.apply_base_stats(e.stats)
	var st: Variant = d.get("stats", {})
	if st is Dictionary:
		for k in st:
			if st[k] is float or st[k] is int:
				e.stats.set_base(str(k), float(st[k]))
			else:
				errs.append("stats.%s debe ser numerico" % str(k))
	else:
		errs.append("'stats' debe ser un objeto")
	if float(e.stats.get_base("HP")) <= 0.0:
		errs.append("HP debe ser > 0")
	warns.append("costes de creacion no evaluados (fase 6): perfil '%s' es ilustrativo" % profile.id)

	var res: Variant = d.get("resources", {})
	if res is Dictionary:
		for rid in res:
			if res[rid] is Dictionary:
				e.resources[str(rid)] = ResourceState.from_dict(str(rid), res[rid])
			else:
				errs.append("resources.%s debe ser un objeto" % str(rid))
	else:
		errs.append("'resources' debe ser un objeto")

	if bool(d.get("basic_attack", true)):
		var ba := _basic_attack(rules, registry)
		if ba.is_empty():
			errs.append("no se pudo construir el ataque basico del reglamento")
		else:
			e.abilities.append(ba["ability"])

	var ability_list: Variant = d.get("abilities", [])
	if ability_list is Array:
		for ad in ability_list:
			if not (ad is Dictionary):
				errs.append("cada habilidad debe ser un objeto")
				continue
			var r := AbilityDef.from_dict(ad, registry)
			if r["ability"] == null:
				errs.append_array(r["errors"])
			elif e.get_ability(r["ability"].id) != null:
				errs.append("habilidad duplicada '%s'" % r["ability"].id)
			else:
				_check_cost_resources(r["ability"], e, errs)
				e.abilities.append(r["ability"])
	else:
		errs.append("'abilities' debe ser una lista")

	var sts: Variant = d.get("statuses", [])
	if sts is Array:
		var probe := StatusCatalog.new()
		for sd in sts:
			if sd is Dictionary:
				var sr := StatusDef.from_dict(sd, registry)
				if sr["def"] == null:
					errs.append_array(sr["errors"])
				elif probe.register(sr["def"]) != "":
					errs.append("estado duplicado '%s'" % str(sd.get("id", "")))
				else:
					e.custom_statuses.append((sd as Dictionary).duplicate(true))
			else:
				errs.append("cada estado debe ser un objeto")
	else:
		errs.append("'statuses' debe ser una lista")
	var sm: Variant = d.get("summons", {})
	if sm is Dictionary:
		for sid in sm:
			if not (sm[sid] is Dictionary):
				errs.append("summons.%s debe ser un objeto" % str(sid))
				continue
			var probe_data: Dictionary = (sm[sid] as Dictionary).duplicate(true)
			probe_data["id"] = "probe"
			probe_data["team"] = "probe"
			if probe_data.has("summons") and not (probe_data["summons"] as Dictionary).is_empty():
				pass # las invocaciones pueden invocar (profundidad limitada por el motor)
			var pr := build(probe_data, profile, rules, registry)
			for pe in pr["errors"]:
				errs.append("summons.%s: %s" % [str(sid), str(pe)])
			e.summon_templates[str(sid)] = (sm[sid] as Dictionary).duplicate(true)
	else:
		errs.append("'summons' debe ser un objeto")

	# Scripts SimScript (solo se compilan aqui: nunca se ejecutan al construir la entidad).
	var failed_scripts := {}
	var sc: Variant = d.get("scripts", {})
	if sc is Dictionary:
		var lim := ScriptLimits.from_ruleset(rules)
		if (sc as Dictionary).size() > 32:
			errs.append("scripts: maximo 32 scripts por entidad")
		for sid in sc:
			if not RegEx.create_from_string("^[a-z][a-z0-9_]{0,63}$").search(str(sid)):
				errs.append("scripts: nombre invalido '%s' (minusculas, digitos y _)" % str(sid))
			elif not (sc[sid] is String):
				errs.append("scripts.%s debe ser texto (codigo SimScript)" % str(sid))
			else:
				var cr := ScriptCompiler.compile(sc[sid], "%s.sim" % str(sid), lim)
				errs.append_array(cr["errors"])
				if cr["program"] != null:
					e.scripts[str(sid)] = cr["program"]
				else:
					failed_scripts[str(sid)] = true
	else:
		errs.append("'scripts' debe ser un objeto {id: codigo}")

	var artifact_ai_rules: Array = []
	if d.has("artifact"):
		artifact_ai_rules = _apply_artifact(d["artifact"], e, registry, profile, rules, errs)

	if d.has("ai"):
		var ai_res := AIFactory.build(d["ai"])
		errs.append_array(ai_res["errors"])
		e.ai = ai_res["ai"]
		if e.ai != null:
			for aid in e.ai.referenced_abilities():
				if e.get_ability(str(aid)) == null:
					errs.append("ia: usa la habilidad inexistente '%s'" % str(aid))
	else:
		var basic: AbilityDef = null
		for a in e.abilities:
			if a.is_basic_attack:
				basic = a
		e.ai = AIFactory.default_attacker(basic.id) if basic != null else PassiveAI.new()

	if not artifact_ai_rules.is_empty():
		for rule in artifact_ai_rules:
			if e.get_ability(str(rule["ability"])) == null:
				errs.append("artifact.ai_rules: la regla usa la habilidad inexistente '%s'" % str(rule["ability"]))
		if e.ai is PriorityListAI:
			var merged: Array = artifact_ai_rules.duplicate(true)
			merged.append_array((e.ai as PriorityListAI).rules)
			(e.ai as PriorityListAI).rules = merged
		elif e.ai is ScoredAI or e.ai is StateMachineAI or e.ai is BehaviorTreeAI:
			e.ai = OverlayAI.wrap(e.ai, artifact_ai_rules)
		else:
			errs.append("artifact.ai_rules requiere una IA priority_list, scored, state_machine o behavior_tree")

	# Enlace de scripts: referencias de efectos e IAs, contexto y llamadas permitidas.
	var used := {}
	for ab in e.abilities:
		_check_script_refs(ab.effects, "habilidad '%s'" % ab.id, e, used, errs, failed_scripts)
	for sd in e.custom_statuses:
		_check_script_refs(sd, "estado '%s'" % str((sd as Dictionary).get("id", "?")), e, used, errs, failed_scripts)
	if e.ai != null:
		var lim2 := ScriptLimits.from_ruleset(rules)
		errs.append_array(e.ai.bind_scripts(e.scripts, lim2))
		for sid2 in e.scripts:
			if JSON.stringify(d.get("ai", {})).contains("\"%s\"" % sid2):
				used[sid2] = true
	for sid3 in e.scripts:
		if not used.has(sid3):
			warns.append("scripts: '%s' no se usa en ninguna habilidad ni IA" % sid3)
		else:
			warns.append("scripts: '%s' no es evaluable automaticamente por el perfil de equilibrio (fase 6): no se le asigna coste" % sid3)

	if not errs.is_empty():
		return {"entity": null, "errors": errs, "warnings": warns}
	return {"entity": e, "errors": errs, "warnings": warns}


## Recorre datos de efectos buscando operaciones `script` y comprueba referencia y contexto.
static func _check_script_refs(node: Variant, where: String, e: CombatEntity, used: Dictionary, errs: Array, failed: Dictionary) -> void:
	if node is Array:
		for x in node:
			_check_script_refs(x, where, e, used, errs, failed)
	elif node is Dictionary:
		if str(node.get("type", "")) == "script" and node.has("script"):
			var sid := str(node["script"])
			if failed.has(sid):
				used[sid] = true # ya se informo del error de compilacion
			elif not e.scripts.has(sid):
				errs.append("%s: usa el script inexistente '%s'" % [where, sid])
			else:
				used[sid] = true
				for er in (e.scripts[sid] as ScriptProgram).check_context(ScriptApi.EFFECT):
					errs.append("%s: %s" % [where, str(er)])
				if node.get("contract", null) is Dictionary:
					for er2 in (e.scripts[sid] as ScriptProgram).check_contract(node["contract"]):
						errs.append("%s: %s" % [where, str(er2)])
		for k in node:
			if str(k) != "args":
				_check_script_refs(node[k], where, e, used, errs, failed)


## Artefacto unico opcional: modificadores de estadisticas y habilidades propias.
## (Pasivas, reacciones, recursos y scripts del artefacto: fase 3.)
static func _apply_artifact(art: Variant, e: CombatEntity, registry: OperationRegistry, profile: BalanceProfile, rules: Ruleset, errs: Array) -> Array:
	if not (art is Dictionary):
		errs.append("'artifact' debe ser un objeto")
		return []
	var a: Dictionary = art
	for k in a:
		if not ARTIFACT_KEYS.has(str(k)):
			errs.append("artifact: propiedad desconocida '%s' (permitidas: %s)" % [str(k), ", ".join(ARTIFACT_KEYS)])
	var art_id := str(a.get("id", ""))
	if art_id == "":
		errs.append("artifact sin 'id'")
	var res0: Variant = a.get("resources", {})
	if res0 is Dictionary:
		for rid in res0:
			if e.resources.has(str(rid)):
				errs.append("artifact: el recurso '%s' ya existe en el personaje" % str(rid))
			elif res0[rid] is Dictionary:
				e.resources[str(rid)] = ResourceState.from_dict(str(rid), res0[rid])
			else:
				errs.append("artifact.resources.%s debe ser un objeto" % str(rid))
	else:
		errs.append("artifact.resources debe ser un objeto")
	var kinds := {"set": StatModifier.Kind.SET, "flat": StatModifier.Kind.FLAT, "pct_add": StatModifier.Kind.PCT_ADD,
		"mult": StatModifier.Kind.MULT, "min": StatModifier.Kind.MIN, "max": StatModifier.Kind.MAX}
	var mods: Variant = a.get("modifiers", [])
	if mods is Array:
		for i in (mods as Array).size():
			var m: Variant = mods[i]
			if not (m is Dictionary):
				errs.append("artifact.modifiers[%d] debe ser un objeto" % i)
				continue
			for k in m:
				if not MODIFIER_KEYS.has(str(k)):
					errs.append("artifact.modifiers[%d]: propiedad desconocida '%s'" % [i, str(k)])
			if str(m.get("stat", "")) == "":
				errs.append("artifact.modifiers[%d]: falta 'stat'" % i)
			elif not kinds.has(str(m.get("kind", ""))):
				errs.append("artifact.modifiers[%d]: kind invalido '%s' (use %s)" % [i, str(m.get("kind", "")), ", ".join(kinds.keys())])
			elif not (m.get("value", null) is float or m.get("value", null) is int):
				errs.append("artifact.modifiers[%d]: 'value' debe ser numerico" % i)
			else:
				e.stats.add_modifier(StatModifier.make(str(m["stat"]), kinds[str(m["kind"])], float(m["value"]), "artifact:" + art_id, int(m.get("priority", 0))))
	else:
		errs.append("artifact.modifiers debe ser una lista")
	var abl: Variant = a.get("abilities", [])
	if abl is Array:
		for ad in abl:
			if not (ad is Dictionary):
				errs.append("artifact.abilities: cada habilidad debe ser un objeto")
				continue
			var r := AbilityDef.from_dict(ad, registry)
			if r["ability"] == null:
				errs.append_array(r["errors"])
			elif e.get_ability(r["ability"].id) != null:
				errs.append("habilidad duplicada '%s' (artefacto)" % r["ability"].id)
			else:
				_check_cost_resources(r["ability"], e, errs)
				e.abilities.append(r["ability"])
	else:
		errs.append("artifact.abilities debe ser una lista")
	return _apply_artifact_extras(a, e, registry, profile, rules, errs)


## Bloques adicionales del artefacto (mismas herramientas que una habilidad/PJ):
## recursos, estados propios, plantillas de invocacion y reglas de IA propias.
static func _apply_artifact_extras(a: Dictionary, e: CombatEntity, registry: OperationRegistry, profile: BalanceProfile, rules: Ruleset, errs: Array) -> Array:
	var ai_rules: Array = []
	var sts: Variant = a.get("statuses", [])
	if sts is Array:
		var probe := StatusCatalog.new()
		for sd in e.custom_statuses:
			if sd is Dictionary:
				probe.register_all([sd], registry)
		for sd in sts:
			if not (sd is Dictionary):
				errs.append("artifact.statuses: cada estado debe ser un objeto")
				continue
			var already := false
			for ex in e.custom_statuses:
				if str(ex.get("id", "")) == str(sd.get("id", "")):
					already = true
					if JSON.stringify(ex, "", true) != JSON.stringify(sd, "", true):
						errs.append("artifact: el estado '%s' ya esta definido con otro contenido" % str(sd.get("id", "")))
			var sr := StatusDef.from_dict(sd, registry)
			if sr["def"] == null:
				errs.append_array(sr["errors"])
			elif not already:
				e.custom_statuses.append((sd as Dictionary).duplicate(true))
	else:
		errs.append("artifact.statuses debe ser una lista")
	var sm: Variant = a.get("summons", {})
	if sm is Dictionary:
		for sid in sm:
			if e.summon_templates.has(str(sid)):
				errs.append("artifact: la plantilla de invocacion '%s' ya existe" % str(sid))
			elif sm[sid] is Dictionary:
				var pd: Dictionary = (sm[sid] as Dictionary).duplicate(true)
				pd["id"] = "probe"
				pd["team"] = "probe"
				for pe in build(pd, profile, rules, registry)["errors"]:
					errs.append("artifact.summons.%s: %s" % [str(sid), str(pe)])
				e.summon_templates[str(sid)] = (sm[sid] as Dictionary).duplicate(true)
			else:
				errs.append("artifact.summons.%s debe ser un objeto" % str(sid))
	else:
		errs.append("artifact.summons debe ser un objeto")
	var ar: Variant = a.get("ai_rules", [])
	if ar is Array:
		var chk := PriorityListAI.validate({"rules": ar})
		errs.append_array(chk)
		if chk.is_empty():
			ai_rules = (ar as Array).duplicate(true)
	else:
		errs.append("artifact.ai_rules debe ser una lista")
	return ai_rules


static func _check_cost_resources(a: AbilityDef, e: CombatEntity, errs: Array) -> void:
	for rid in a.cost:
		if not e.resources.has(rid):
			errs.append("habilidad '%s': coste en recurso inexistente '%s'" % [a.id, rid])


static func _basic_attack(rules: Ruleset, registry: OperationRegistry) -> Dictionary:
	var ba: Dictionary = rules.get_path_value("basic_attack")
	var r := AbilityDef.from_dict({
		"id": str(ba["id"]), "name": str(ba["name"]), "action_type": "main", "targeting": "enemy",
		"effects": [{
			"type": "damage", "can_crit": bool(ba.get("can_crit", true)),
			"components": [{"damage_type": str(ba["damage_type"]), "element": str(ba.get("element", "")), "formula": str(ba["formula"])}],
		}],
	}, registry)
	if r["ability"] == null:
		return {}
	(r["ability"] as AbilityDef).is_basic_attack = true
	return {"ability": r["ability"]}


static func load_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())
