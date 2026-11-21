extends SceneTree
## Ejecuta un lote de simulaciones desde un archivo JSON de plan (BatchPlan, `simhalla.batch/1`). Sin UI.
##   godot --headless --path . --script res://tools/batch_tool.gd -- <plan.json> [--workers N] [--out resultado.json]
##        [--keep-traces] [--quiet]
## Imprime el progreso (stderr) y un resumen (stdout). Codigo de salida: 0 completo, 3 cancelado/parcial, 2 error de plan.
## Resultado reproducible: la huella (`fingerprint`) no depende del numero de workers ni del orden.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	var workers := 0
	var out := ""
	var keep := false
	var quiet := false
	var i := 0
	while i < args.size():
		match args[i]:
			"--workers":
				workers = int(args[i + 1])
				i += 2
			"--out":
				out = args[i + 1]
				i += 2
			"--keep-traces":
				keep = true
				i += 1
			"--quiet":
				quiet = true
				i += 1
			_:
				path = args[i]
				i += 1
	if path == "":
		printerr("uso: batch_tool.gd -- <plan.json> [--workers N] [--out resultado.json] [--keep-traces] [--quiet]")
		quit(2)
		return
	var cfg: Variant = EntityFactory.load_json(path)
	if not (cfg is Dictionary):
		printerr("no se pudo leer un objeto JSON de '%s'" % path)
		quit(2)
		return
	var built := BatchPlan.from_dict(cfg)
	if built["plan"] == null:
		for e in built["errors"]:
			printerr("plan: " + str(e))
		quit(2)
		return
	var plan: BatchPlan = built["plan"]
	var runner := BatchRunner.new(plan, {"workers": workers, "keep_traces": keep})
	runner.start()
	var last := -1
	if workers <= 0:
		while runner.run_slice(8)["pending"] > 0:
			last = _report(runner.progress(), last, quiet)
	else:
		while not runner.is_finished():
			last = _report(runner.poll(), last, quiet)
			OS.delay_msec(20)
	var res := runner.wait()
	print("lote '%s': %d/%d trabajos (%s) huella=%s" % [plan.name, res.executed, res.total_jobs, res.status, res.fingerprint.substr(0, 16)])
	print("  %.1f duelos/s, %.0f eventos/s, workers=%d, %d ms" % [res.perf["jobs_per_s"], res.perf["events_per_s"], res.perf["workers"], res.perf["wall_ms"]])
	var t: Dictionary = res.summary["totals"]
	print("  resueltos %d (victorias %d, empates %d) · abortos tecnicos %d · errores de preparacion %d · cancelados %d" % [t["finished"], t["wins"], t["draws"], t["aborted"], t["setup_errors"], t["cancelled"]])
	for s in res.summary["scenarios"]:
		print("  - %s: n=%d %s empates=%d turnos medios=%.1f" % [s["key"], s["n_finished"], str(s["wins_by_label"]), s["draws"], float(s["turns"]["mean"])])
	if out != "":
		var f := FileAccess.open(out, FileAccess.WRITE)
		f.store_string(JSON.stringify(res.to_dict(), "  "))
		f.close()
	quit(0 if res.is_complete() else 3)


func _report(p: Dictionary, last: int, quiet: bool) -> int:
	if not quiet and int(p["done"]) != last:
		printerr("progreso: %d/%d" % [p["done"], p["total"]])
	return int(p["done"])
