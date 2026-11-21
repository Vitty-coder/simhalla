extends SceneTree
## Genera informes (JSON + Markdown + HTML) de un combate o de un lote. Sin UI.
##   godot --headless --path . --script res://tools/report_tool.gd -- duel <a.json> <b.json> <semilla> [--history none|summary|full] [--balance perfil.json] [--out dir] [--name base]
##   godot --headless --path . --script res://tools/report_tool.gd -- batch <plan.json> [--workers N] [--out dir] [--name base]
## `--out` por defecto: user://reports. Escribe <name>.json/.md/.html y muestra la huella del informe.
## Salida 0 correcto, 2 error de entrada.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	if args.size() < 2:
		printerr("uso: report_tool.gd -- duel <a.json> <b.json> <semilla> [opciones] | batch <plan.json> [opciones]")
		quit(2)
		return
	var opts := {"out": "user://reports", "name": "", "history": "summary", "workers": 0, "balance": ""}
	var pos: Array[String] = []
	var i := 1
	while i < args.size():
		if args[i].begins_with("--") and i + 1 < args.size():
			opts[args[i].substr(2)] = args[i + 1]
			i += 2
		else:
			pos.append(args[i])
			i += 1
	var code := 0
	match args[0]:
		"duel":
			code = _duel(pos, opts)
		"batch":
			code = _batch(pos, opts)
		_:
			printerr("orden desconocida '%s'" % args[0])
			code = 2
	quit(code)


func _write(model: Dictionary, opts: Dictionary, default_name: String) -> int:
	var base: String = str(opts["name"]) if str(opts["name"]) != "" else default_name
	var out := ReportExporter.write_all(model, str(opts["out"]), base)
	for e in out["errors"]:
		printerr(e)
	for p in out["paths"]:
		print("escrito: ", ProjectSettings.globalize_path(p))
	print("huella del informe: ", ReportExporter.content_hash(model))
	return 2 if not out["errors"].is_empty() else 0


func _duel(pos: Array[String], opts: Dictionary) -> int:
	if pos.size() < 3:
		printerr("uso: duel <a.json> <b.json> <semilla>")
		return 2
	var cfg := {"seed": int(pos[2]), "entities": [{"path": pos[0], "overrides": {"id": "a", "team": "A"}}, {"path": pos[1], "overrides": {"id": "b", "team": "B"}}]}
	var o := SimulationSession.open(cfg)
	if not bool(o["ok"]):
		for e in o["errors"]:
			printerr(str(e))
		return 2
	var s: SimulationSession = o["session"]
	s.run_to_end()
	var ropts := {"config": cfg, "history": str(opts["history"])}
	if str(opts["balance"]) != "":
		var prof := BalanceProfile.from_file(str(opts["balance"]))
		var data: Variant = EntityFactory.load_json(pos[0])
		if prof.is_valid() and data is Dictionary:
			ropts["balance"] = BalanceEvaluator.evaluate(data, prof, Ruleset.from_file(DuelRunner.DEFAULT_RULESET), OperationRegistry.new(), {"mode": "free"}).to_dict()
	var r := IndividualReport.build(s.engine, ropts)
	if not bool(r["ok"]):
		printerr(str(r["errors"]))
		return 2
	return _write(r["report"], opts, "combate_%s" % pos[2])


func _batch(pos: Array[String], opts: Dictionary) -> int:
	if pos.is_empty():
		printerr("uso: batch <plan.json>")
		return 2
	var cfg: Variant = EntityFactory.load_json(pos[0])
	if not (cfg is Dictionary):
		printerr("no se pudo leer '%s'" % pos[0])
		return 2
	var built := BatchPlan.from_dict(cfg)
	if built["plan"] == null:
		for e in built["errors"]:
			printerr("plan: " + str(e))
		return 2
	var res := BatchRunner.new(built["plan"], {"workers": int(opts["workers"])}).wait()
	var m := BatchReport.build(res)
	for e in ReportVerifier.check_batch(m):
		printerr("incoherencia: " + str(e))
	return _write(m, opts, "lote_%s" % (built["plan"] as BatchPlan).name.replace(" ", "_"))
