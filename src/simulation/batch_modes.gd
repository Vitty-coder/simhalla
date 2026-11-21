class_name BatchModes
extends RefCounted
## Constructores de las modalidades de lote (PROJECT.md §13). Todos devuelven un diccionario de lote
## (`BatchPlan.from_dict`). Una "entidad" es una especificacion de DuelRunner: {"path"|"package", "version"?,
## "overrides"?, "patch"?}; los constructores asignan equipos A/B (los `overrides` del usuario se respetan salvo `team`).
## `label` identifica al contendiente en los resultados.

static func _with_team(spec: Dictionary, team: String, id: String = "") -> Dictionary:
	var s: Dictionary = spec.duplicate(true)
	var ov: Dictionary = (s.get("overrides", {}) as Dictionary).duplicate(true)
	ov["team"] = team
	if id != "" and not ov.has("id"):
		ov["id"] = id
	s["overrides"] = ov
	return s


static func _scenario(key: String, label: String, a: Dictionary, b: Dictionary, la: String, lb: String, params: Dictionary = {}) -> Dictionary:
	return {"key": key, "label": label, "entities": [_with_team(a, "A", "a"), _with_team(b, "B", "b")], "sides": {"A": la, "B": lb}, "params": params}


static func _batch(name: String, master_seed: int, reps: int, scenarios: Array, base: Dictionary, seed_mode: String = "per_scenario") -> Dictionary:
	return {"schema": BatchPlan.SCHEMA, "name": name, "master_seed": master_seed, "repetitions": reps, "seed_mode": seed_mode, "base": base, "scenarios": scenarios}


## Repeticion de un duelo A vs B.
static func duel(a: Dictionary, b: Dictionary, reps: int, master_seed: int, base: Dictionary = {}, label_a: String = "A", label_b: String = "B") -> Dictionary:
	return _batch("duel", master_seed, reps, [_scenario("a_vs_b", "%s vs %s" % [label_a, label_b], a, b, label_a, label_b)], base)


## Todos contra todos como duelos 1v1. contestants: [{label, spec}]. `both_sides`: tambien con los equipos intercambiados
## (el orden de equipos puede afectar a desempates).
static func tournament(contestants: Array, reps: int, master_seed: int, base: Dictionary = {}, both_sides: bool = true) -> Dictionary:
	var sc: Array = []
	for i in contestants.size():
		for j in range(i + 1, contestants.size()):
			var ci: Dictionary = contestants[i]
			var cj: Dictionary = contestants[j]
			sc.append(_scenario("%s__vs__%s" % [ci["label"], cj["label"]], "%s vs %s" % [ci["label"], cj["label"]], ci["spec"], cj["spec"], ci["label"], cj["label"]))
			if both_sides:
				sc.append(_scenario("%s__vs__%s" % [cj["label"], ci["label"]], "%s vs %s" % [cj["label"], ci["label"]], cj["spec"], ci["spec"], cj["label"], ci["label"]))
	return _batch("tournament", master_seed, reps, sc, base)


## PJ de prueba contra una biblioteca de adversarios. opponents: [{label, spec}].
static func gauntlet(subject: Dictionary, opponents: Array, reps: int, master_seed: int, base: Dictionary = {}) -> Dictionary:
	var sc: Array = []
	for o in opponents:
		sc.append(_scenario("subject__vs__%s" % o["label"], "%s vs %s" % [subject["label"], o["label"]], subject["spec"], o["spec"], subject["label"], o["label"]))
	return _batch("gauntlet", master_seed, reps, sc, base)


## Compara variantes (versiones de un PJ/componente, perfiles de IA...) contra el MISMO adversario. variants: [{label, spec}].
## `paired` (por defecto): mismas semillas por repeticion en todas las variantes (comparacion emparejada).
static func compare_variants(variants: Array, opponent: Dictionary, reps: int, master_seed: int, base: Dictionary = {}, paired: bool = true) -> Dictionary:
	var sc: Array = []
	for v in variants:
		var s := _scenario("variant__%s" % v["label"], "%s vs %s" % [v["label"], opponent["label"]], v["spec"], opponent["spec"], v["label"], opponent["label"], {"variant": v["label"]})
		s["group"] = "compare"
		sc.append(s)
	return _batch("compare_variants", master_seed, reps, sc, base, "paired" if paired else "per_scenario")


## Compara perfiles de IA para el mismo PJ: `ais` = [{label, ai}] se aplica como override `ai` del primer contendiente.
static func compare_ai(subject: Dictionary, ais: Array, opponent: Dictionary, reps: int, master_seed: int, base: Dictionary = {}, paired: bool = true) -> Dictionary:
	var variants: Array = []
	for a in ais:
		var spec: Dictionary = subject["spec"].duplicate(true)
		var ov: Dictionary = (spec.get("overrides", {}) as Dictionary).duplicate(true)
		ov["ai"] = a["ai"]
		spec["overrides"] = ov
		variants.append({"label": "%s[%s]" % [subject["label"], a["label"]], "spec": spec})
	return compare_variants(variants, opponent, reps, master_seed, base, paired)


## Compara reglamentos globales para el mismo duelo. rulesets: [{label, overrides}] (fusion profunda sobre el reglamento base).
static func compare_rulesets(a: Dictionary, b: Dictionary, rulesets: Array, reps: int, master_seed: int, base: Dictionary = {}, paired: bool = true) -> Dictionary:
	var sc: Array = []
	for r in rulesets:
		var s := _scenario("ruleset__%s" % r["label"], "ruleset %s" % r["label"], a, b, str(a.get("label", "A")), str(b.get("label", "B")), {"ruleset": r["label"]})
		s["entities"] = [_with_team(a["spec"], "A", "a"), _with_team(b["spec"], "B", "b")]
		s["sides"] = {"A": str(a["label"]), "B": str(b["label"])}
		s["ruleset_overrides"] = (r["overrides"] as Dictionary).duplicate(true)
		s["group"] = "rules"
		sc.append(s)
	return _batch("compare_rulesets", master_seed, reps, sc, base, "paired" if paired else "per_scenario")


## Variacion controlada de parametros: producto cartesiano de ejes sobre una entidad (`target`: 0 = primera, 1 = segunda).
## axes: [{"path": "stats.ATK", "values": [..]}]; cada combinacion es un escenario con `params`. Maximo `max_scenarios`.
static func sweep(a: Dictionary, b: Dictionary, axes: Array, target: int, reps: int, master_seed: int, base: Dictionary = {}, paired: bool = true, max_scenarios: int = 1000) -> Dictionary:
	var combos: Array = [{}]
	for ax in axes:
		var next: Array = []
		for c in combos:
			for v in ax["values"]:
				var n: Dictionary = c.duplicate()
				n[str(ax["path"])] = v
				next.append(n)
		combos = next
		if combos.size() > max_scenarios:
			return _batch("sweep", master_seed, reps, [], base) # se rechaza al planificar (sin escenarios)
	var sc: Array = []
	for c in combos:
		var spec_a: Dictionary = a["spec"].duplicate(true)
		var spec_b: Dictionary = b["spec"].duplicate(true)
		var patch: Dictionary = {}
		var key_parts: Array = []
		var paths: Array = c.keys()
		paths.sort()
		for path in paths:
			_set_path(patch, str(path), c[path])
			key_parts.append("%s=%s" % [path, str(c[path])])
		var tgt: Dictionary = spec_a if target == 0 else spec_b
		tgt["patch"] = Ruleset._merge(tgt.get("patch", {}), patch)
		var key := "sweep__" + "__".join(key_parts) if not key_parts.is_empty() else "sweep__base"
		var s := _scenario(key, key, spec_a, spec_b, str(a["label"]), str(b["label"]), c)
		s["group"] = "sweep"
		sc.append(s)
	return _batch("sweep", master_seed, reps, sc, base, "paired" if paired else "per_scenario")


static func _set_path(d: Dictionary, path: String, value: Variant) -> void:
	var parts := path.split(".")
	if parts[0] == "stats" and parts.size() > 1: # los ids de estadistica pueden contener '.' (ELEM_AFF.fire): se toman enteros
		if not d.has("stats") or not (d["stats"] is Dictionary):
			d["stats"] = {}
		d["stats"][".".join(parts.slice(1))] = value
		return
	var cur := d
	for i in parts.size() - 1:
		if not cur.has(parts[i]) or not (cur[parts[i]] is Dictionary):
			cur[parts[i]] = {}
		cur = cur[parts[i]]
	cur[parts[parts.size() - 1]] = value
