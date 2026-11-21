class_name DuelSetupModel
extends RefCounted
## Modelo de la pantalla Configuracion de duelo: contendientes (paquetes con restriccion de version, o archivos), IA alternativa,
## parametros sueltos (`patch`), reglamento, perfil de equilibrio, modo libre/reglamentado, presupuesto, semilla y estado inicial.
## `validate()` muestra ANTES del combate: version y huella exactas que se usaran, coste calculado frente al presupuesto,
## advertencias y validacion; en modo reglamentado los incumplimientos bloquean (`can_start = false`); en libre solo avisan.

var app: AppController
var entities: Array = [] ## [{package|path, constraint, team, ai, patch, name}]
var ruleset_id: String = "builtin/default_ruleset"
var ruleset_constraint: String = "*"
var profile_id: String = ""
var mode: String = ""
var budget: String = ""
var seed_value: int = 1
var initial_overrides: Dictionary = {}


func _init(a: AppController) -> void:
	app = a
	reset()


func reset() -> void:
	entities.clear()
	profile_id = str(app.settings()["default_profile"])
	mode = app.mode()
	budget = app.budget()
	seed_value = 1
	initial_overrides = {}


func add_package(id: String, constraint: String = "*", team: String = "", ai: Variant = null, patch: Dictionary = {}) -> int:
	entities.append({"package": id, "constraint": constraint, "team": team if team != "" else _next_team(), "ai": ai, "patch": patch.duplicate(true), "name": id})
	return entities.size() - 1


func add_file(path: String, team: String = "") -> int:
	entities.append({"path": path, "constraint": "", "team": team if team != "" else _next_team(), "ai": null, "patch": {}, "name": path.get_file().get_basename()})
	return entities.size() - 1


func remove(i: int) -> void:
	if i >= 0 and i < entities.size():
		entities.remove_at(i)


func _next_team() -> String:
	var used := {}
	for e in entities:
		used[e["team"]] = true
	for t in ["A", "B", "C", "D", "E", "F"]:
		if not used.has(t):
			return t
	return "Z"


func _entity_id(i: int) -> String:
	return "e%d" % (i + 1)


## Datos de entidad de la configuracion i (con `ai` y `patch` aplicados). {"ok","data","resolved":{id,version,hash},"errors"}.
func entity_data(i: int) -> Dictionary:
	var e: Dictionary = entities[i]
	var data: Dictionary = {}
	var resolved := {}
	if e.has("package"):
		var r := app.storage.library.resolve(str(e["package"]), str(e["constraint"]))
		if r.is_empty():
			return {"ok": false, "data": {}, "resolved": {}, "errors": ["[no_encontrado] ningun paquete '%s' cumple '%s'" % [str(e["package"]), str(e["constraint"])]]}
		var c := app.library.compose(str(e["package"]), str(r["version"]))
		if not bool(c["ok"]):
			return {"ok": false, "data": {}, "resolved": {}, "errors": c["errors"]}
		data = c["data"]
		resolved = {"id": r["id"], "version": r["version"], "hash": r["hash"]}
	else:
		var d: Variant = EntityFactory.load_json(str(e["path"]))
		if not (d is Dictionary):
			return {"ok": false, "data": {}, "resolved": {}, "errors": ["no se pudo leer '%s'" % str(e["path"])]}
		data = d
	if e["ai"] != null:
		data["ai"] = e["ai"]
	if not (e["patch"] as Dictionary).is_empty():
		data = Ruleset._merge(data, e["patch"])
	data["id"] = _entity_id(i)
	data["team"] = e["team"]
	return {"ok": true, "data": data, "resolved": resolved, "errors": []}


## Validacion previa al combate. {"ok","can_start","mode","mode_label","budget","profile","entities":[...],"errors","warnings"}.
func validate() -> Dictionary:
	var errs: Array = []
	var warns: Array = []
	var rows: Array = []
	var teams := {}
	for i in entities.size():
		var ed := entity_data(i)
		if not bool(ed["ok"]):
			errs.append_array(ed["errors"])
			rows.append({"name": entities[i]["name"], "team": entities[i]["team"], "ok": false, "errors": ed["errors"]})
			continue
		teams[entities[i]["team"]] = true
		var cr := app.cost_report(ed["data"], {"profile": profile_id, "mode": mode, "budget": budget})
		for t in cr["technical_errors"]:
			errs.append("%s: %s" % [entities[i]["name"], str(t)])
		if mode == "regulated":
			for er in cr["errors"]:
				errs.append("%s: %s" % [entities[i]["name"], str(er)])
		for w in cr["warnings"]:
			if not str(w).begins_with("perfil ilustrativo"):
				warns.append("%s: %s" % [entities[i]["name"], str(w)])
		rows.append({"name": entities[i]["name"], "team": entities[i]["team"], "ok": (cr["technical_errors"] as Array).is_empty() and (mode != "regulated" or (cr["errors"] as Array).is_empty()),
			"resolved": ed["resolved"], "cost": cr["creation_cost"], "budget_points": cr["budget"]["points"], "remaining": cr["remaining"], "within_budget": cr["within_budget"],
			"unevaluable": cr["unevaluable"].size(), "labels": cr["labels"], "balance": cr})
	if entities.size() < 2:
		errs.append(LocaleService.t("duel.err_two_entities"))
	elif teams.size() < 2:
		errs.append(LocaleService.t("duel.err_two_teams"))
	var rs := app.storage.rulesets.latest(ruleset_id) if ruleset_constraint == "*" else app.storage.rulesets.resolve(ruleset_id, ruleset_constraint)
	if rs.is_empty():
		errs.append("[no_encontrado] reglamento '%s' (%s)" % [ruleset_id, ruleset_constraint])
	var prof := app.profile(profile_id)
	if not prof.is_valid():
		errs.append("perfil de equilibrio invalido: " + "; ".join(prof.errors))
	return {"ok": errs.is_empty(), "can_start": errs.is_empty(), "mode": mode, "mode_label": LocaleService.t("mode." + mode), "budget": budget,
		"profile": {"id": prof.id, "version": prof.version, "illustrative": prof.illustrative}, "ruleset": rs, "entities": rows, "errors": errs, "warnings": warns,
		"illustrative_notice": LocaleService.t("balance.illustrative") if prof.illustrative else ""}


## Configuracion de DuelRunner SIN fijar (restricciones de version tal cual).
func to_config() -> Dictionary:
	var specs: Array = []
	for i in entities.size():
		var e: Dictionary = entities[i]
		var ov := {"id": _entity_id(i), "team": e["team"]}
		var spec: Dictionary = {"overrides": ov}
		if e.has("package"):
			spec["package"] = e["package"]
			spec["version"] = e["constraint"]
		else:
			spec["path"] = e["path"]
		if e["ai"] != null:
			ov["ai"] = e["ai"]
		if not (e["patch"] as Dictionary).is_empty():
			spec["patch"] = e["patch"]
		specs.append(spec)
	var cfg := {"seed": seed_value, "entities": specs}
	var rs := app.storage.rulesets.latest(ruleset_id) if ruleset_constraint == "*" else app.storage.rulesets.resolve(ruleset_id, ruleset_constraint)
	if not rs.is_empty():
		cfg["ruleset_data"] = app.ruleset(ruleset_id, ruleset_constraint).data
	var prof := app.profile(profile_id)
	cfg["profile_data"] = prof.to_dict()
	if not initial_overrides.is_empty():
		cfg["initial_overrides"] = initial_overrides.duplicate(true)
	return cfg


## Valida, fija versiones/huellas y abre el visor. {"ok","viewer","errors","validation"}.
func start() -> Dictionary:
	var v := validate()
	if not bool(v["can_start"]):
		return {"ok": false, "viewer": null, "errors": v["errors"], "validation": v}
	var pin := app.storage.pin_config(to_config())
	if not bool(pin["ok"]):
		return {"ok": false, "viewer": null, "errors": pin["errors"], "validation": v}
	var vm := ViewerModel.open(app, pin["config"], {"refs": pin["refs"]})
	if not bool(vm["ok"]):
		return {"ok": false, "viewer": null, "errors": vm["errors"], "validation": v}
	app.viewer = vm["viewer"]
	return {"ok": true, "viewer": vm["viewer"], "errors": [], "validation": v}
