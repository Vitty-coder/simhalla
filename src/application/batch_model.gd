class_name BatchModel
extends RefCounted
## Modelo de Configuracion y ejecucion masiva: construye el plan segun la modalidad (duelo, torneo, biblioteca, versiones, IA,
## reglamentos, variacion de parametros), FIJA versiones/huellas de los paquetes, ejecuta con BatchRunner (cooperativo o hilos,
## progreso, cancelacion), guarda el lote y genera el informe.
## spec: {mode, reps, master_seed, paired, contestants:[{label, spec}], subject, opponent, variants, ais, rulesets, axes, target}.

const MODES := ["duel", "tournament", "gauntlet", "compare_variants", "compare_ai", "compare_rulesets", "sweep"]

var app: AppController
var plan: BatchPlan = null
var plan_dict: Dictionary = {}
var refs: Array = []
var runner: BatchRunner = null
var result: BatchResult = null
var saved_id: String = ""


func _init(a: AppController) -> void:
	app = a


## {"ok","errors","plan"}. Fija versiones (paquetes) y entidades sueltas inline.
func prepare(spec: Dictionary) -> Dictionary:
	var mode := str(spec.get("mode", "duel"))
	if not MODES.has(mode):
		return {"ok": false, "errors": ["modalidad desconocida '%s'" % mode], "plan": null}
	var reps := int(spec.get("reps", 10))
	var seed_v := int(spec.get("master_seed", 1))
	var rs := app.ruleset()
	var base := {"library": app.storage.library.root, "ruleset_data": rs.data, "profile_data": app.profile().to_dict()}
	var cfg: Dictionary = {}
	match mode:
		"duel":
			cfg = BatchModes.duel(spec["a"], spec["b"], reps, seed_v, base, str(spec.get("label_a", "A")), str(spec.get("label_b", "B")))
		"tournament":
			cfg = BatchModes.tournament(spec["contestants"], reps, seed_v, base, bool(spec.get("both_sides", true)))
		"gauntlet":
			cfg = BatchModes.gauntlet(spec["subject"], spec["opponents"], reps, seed_v, base)
		"compare_variants":
			cfg = BatchModes.compare_variants(spec["variants"], spec["opponent"], reps, seed_v, base, bool(spec.get("paired", true)))
		"compare_ai":
			cfg = BatchModes.compare_ai(spec["subject"], spec["ais"], spec["opponent"], reps, seed_v, base, bool(spec.get("paired", true)))
		"compare_rulesets":
			cfg = BatchModes.compare_rulesets(spec["a"], spec["b"], spec["rulesets"], reps, seed_v, base, bool(spec.get("paired", true)))
		"sweep":
			cfg = BatchModes.sweep(spec["a"], spec["b"], spec["axes"], int(spec.get("target", 0)), reps, seed_v, base, bool(spec.get("paired", true)), int(spec.get("max_scenarios", 1000)))
	# fijar versiones de paquetes y entidades sueltas (reproducibilidad)
	var errs: Array = []
	refs.clear()
	var seen := {}
	for sc in cfg.get("scenarios", []):
		var pe := app.storage.pin_entities(sc["entities"])
		errs.append_array(pe["errors"])
		sc["entities"] = pe["specs"]
		for r in pe["refs"]:
			var k := "%s@%s" % [r["id"], r["version"]]
			if not seen.has(k):
				seen[k] = true
				refs.append(r)
	if not errs.is_empty():
		return {"ok": false, "errors": errs, "plan": null}
	var built := BatchPlan.from_dict(cfg)
	if built["plan"] == null:
		return {"ok": false, "errors": built["errors"], "plan": null}
	plan = built["plan"]
	plan_dict = plan.to_dict()
	result = null
	saved_id = ""
	return {"ok": true, "errors": [], "plan": plan, "jobs": plan.job_count(), "scenarios": plan.scenarios.size()}


## Lanza la ejecucion (workers 0 = cooperativa: usar `step()`; >= 1 = hilos: usar `poll()`).
func start(workers: int = -1) -> bool:
	if plan == null:
		return false
	var w := workers if workers >= 0 else int(app.settings()["workers"])
	runner = BatchRunner.new(plan, {"workers": w})
	runner.start()
	return true


## Modo cooperativo: ejecuta una porcion y devuelve el progreso.
func step(max_jobs: int = 4, max_ms: int = 8) -> Dictionary:
	if runner == null:
		return {}
	var p := runner.run_slice(max_jobs, max_ms)
	_check_done()
	return p


## Modo hilos (o cualquiera): agrega lo terminado y devuelve el progreso.
func poll() -> Dictionary:
	if runner == null:
		return {}
	var p := runner.poll()
	_check_done()
	return p


func _check_done() -> void:
	if runner != null and result == null and runner.is_finished():
		result = runner.wait()


func progress() -> Dictionary:
	return runner.progress() if runner != null else {}


func is_running() -> bool:
	return runner != null and result == null


func cancel() -> void:
	if runner != null:
		runner.cancel()
		_check_done()


## Bloquea hasta terminar (utilidad para flujos no interactivos).
func finish() -> BatchResult:
	if runner != null and result == null:
		result = runner.wait()
	return result


## Resumen incremental para pintar (progreso y marcador por escenario).
func live_summary() -> Dictionary:
	return runner.accumulator.summary() if runner != null else {}


func save(title: String) -> Dictionary:
	if result == null:
		return {"ok": false, "id": "", "error": "el lote no ha terminado"}
	var r := app.storage.save_batch(result, title, refs)
	if bool(r["ok"]):
		saved_id = r["id"]
	return r


func report() -> Dictionary:
	return BatchReport.build(result) if result != null else {}


func save_report(title: String = "") -> Dictionary:
	if result == null:
		return {"ok": false, "id": "", "error": "el lote no ha terminado"}
	var refs_r: Array = []
	if saved_id != "":
		refs_r.append({"kind": "batch", "id": saved_id})
	return app.storage.save_report(report(), title if title != "" else "Informe del lote %s" % plan.name, refs_r)
