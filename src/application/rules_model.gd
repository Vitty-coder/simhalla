class_name RulesModel
extends RefCounted
## Modelo de la pantalla Reglamentos y equilibrio: reglamentos y perfiles versionados (con validacion y aviso de perfil
## ILUSTRATIVO), perfil activo, importacion de archivos con colision explicita y valoracion de un personaje.

var app: AppController


func _init(a: AppController) -> void:
	app = a


func rulesets() -> Array:
	return app.storage.rulesets.list()


func profiles() -> Array:
	return app.storage.profiles.list()


func ruleset_detail(id: String, version: String) -> Dictionary:
	var g := app.storage.rulesets.get_item(id, version)
	if not bool(g["ok"]):
		return {"ok": false, "error": g["error"]}
	var rs := Ruleset.from_dict(g["data"])
	return {"ok": rs.is_valid(), "errors": rs.errors, "hash": g["hash"], "content_hash": rs.content_hash(), "id": rs.id(), "version": rs.version(),
		"limits": rs.data.get("victory", {}).get("limits", {}), "scripting": rs.data.get("scripting", {}), "elements": rs.data.get("elements", [])}


func profile_detail(id: String, version: String) -> Dictionary:
	var g := app.storage.profiles.get_item(id, version)
	if not bool(g["ok"]):
		return {"ok": false, "error": g["error"]}
	var p := BalanceProfile.from_dict(g["data"])
	return {"ok": p.is_valid(), "errors": p.errors, "hash": g["hash"], "illustrative": p.illustrative, "has_costs": p.has_costs(), "budgets": p.budgets, "default_budget": p.default_budget,
		"base_stats": p.base_stats, "description": p.description, "operations": (p.costs.get("operations", {}) as Dictionary).keys(),
		"notice": LocaleService.t("balance.illustrative") if p.illustrative else ""}


func set_active_profile(id: String) -> Array:
	return app.save_settings({"default_profile": id})


## Importa un reglamento/perfil desde un archivo JSON. policy ante colision: "reject" | "new_version". {"ok","version","error"}.
func import_file(kind: String, path: String, id: String, version: String, policy: String = "reject") -> Dictionary:
	var d: Variant = EntityFactory.load_json(path)
	if not (d is Dictionary):
		return {"ok": false, "version": version, "error": "no se pudo leer un objeto JSON de '%s'" % path}
	var st: VersionedStore = app.storage.rulesets if kind == "ruleset" else app.storage.profiles
	var r := st.put_resolving(id, version, d) if policy == "new_version" else st.put(id, version, d)
	r["version"] = r.get("version", version)
	return r


func evaluate(package_id: String, version: String, profile_id: String, mode: String, budget: String) -> Dictionary:
	var c := app.library.compose(package_id, version)
	if not bool(c["ok"]):
		return {"technical_errors": c["errors"]}
	return app.cost_report(c["data"], {"profile": profile_id, "mode": mode, "budget": budget})


var calib_job: BalanceCalibrator.Job = null
var calib_result: Dictionary = {}


func _contestants(package_ids: Array) -> Dictionary:
	var contestants: Array = []
	var errs: Array = []
	for ref in package_ids:
		# "id" (ultima version) o "id@version"
		var parts := str(ref).split("@")
		var id: String = parts[0]
		var ver: String = parts[1] if parts.size() > 1 else str(app.storage.library.resolve(id, "*").get("version", ""))
		var c := app.library.compose(id, ver)
		if not bool(c["ok"]):
			errs.append("%s: %s" % [ref, "; ".join(c["errors"])])
			continue
		contestants.append({"label": id, "spec": {"package": id, "version": ver}, "data": c["data"]})
	return {"contestants": contestants, "errors": errs}


func _calib_opts(opts: Dictionary) -> Dictionary:
	var o := opts.duplicate()
	if not o.has("base"):
		# los duelos usan la biblioteca, el reglamento y el perfil de la aplicacion (los mismos que valoran los costes)
		o["base"] = {"library": app.storage.library.root, "ruleset_data": app.ruleset().data, "profile_data": app.profile(str(opts.get("profile", ""))).to_dict(),
			"ruleset_overrides": {"victory": {"limits": {"max_turns": 60, "stagnation_turns": 30}}}}
	return o


## Calibra costes empiricamente con personajes de la biblioteca (ver BalanceCalibrator), de forma SINCRONA.
## `package_ids`: ids de paquetes de personaje (>= 4). opts: {profile, reps, master_seed, workers}.
## Devuelve el resultado del calibrador (la propuesta NO se guarda: ver `save_calibrated`).
func calibrate(package_ids: Array, opts: Dictionary = {}) -> Dictionary:
	var c := _contestants(package_ids)
	if not (c["errors"] as Array).is_empty():
		return {"ok": false, "errors": c["errors"], "warnings": []}
	return BalanceCalibrator.calibrate(c["contestants"], app.profile(str(opts.get("profile", ""))), app.ruleset(), OperationRegistry.new(), _calib_opts(opts))


## Version por tramos para la interfaz: prepara el torneo sin ejecutarlo. {"ok", "errors"}.
func begin_calibration(package_ids: Array, opts: Dictionary = {}) -> Dictionary:
	calib_job = null
	calib_result = {}
	var c := _contestants(package_ids)
	if not (c["errors"] as Array).is_empty():
		calib_result = {"ok": false, "errors": c["errors"], "warnings": []}
		return calib_result
	var b := BalanceCalibrator.begin(c["contestants"], app.profile(str(opts.get("profile", ""))), app.ruleset(), OperationRegistry.new(), _calib_opts(opts))
	if not bool(b["ok"]):
		calib_result = b
		return b
	calib_job = b["job"]
	return {"ok": true, "errors": []}


## Avanza ~max_ms. Devuelve true mientras siga en marcha; al terminar deja el resultado en `calib_result`.
func calibration_step(max_ms: int = 8) -> bool:
	if calib_job == null:
		return false
	calib_job.step(max_ms)
	if calib_job.is_done():
		calib_result = calib_job.finish()
		calib_job = null
		return false
	return true


func cancel_calibration() -> void:
	if calib_job != null:
		calib_job.cancel()
		calib_result = calib_job.finish()
		calib_job = null


func calibration_progress() -> Dictionary:
	return calib_job.progress() if calib_job != null else {}


## Guarda la propuesta como perfil versionado (resolviendo colisiones como version nueva). Siempre ILUSTRATIVA. {"ok", "id", "version", "error"}.
func save_calibrated(result: Dictionary) -> Dictionary:
	var sp: Variant = result.get("suggested_profile", null)
	if not (sp is Dictionary):
		return {"ok": false, "error": "no hay perfil propuesto"}
	var r := app.storage.profiles.put_resolving(str(sp["id"]), str(sp["version"]), sp)
	if bool(r["ok"]):
		app.storage.log_event("calibrate", "%s@%s" % [sp["id"], r["version"]], "perfil calibrado (ilustrativo)")
	r["id"] = str(sp["id"])
	return r
