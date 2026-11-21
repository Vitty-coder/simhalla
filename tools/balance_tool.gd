extends SceneTree
## Valoracion de creacion (puntos de creacion) de un personaje. No ejecuta combates.
##   godot --headless --path . --script res://tools/balance_tool.gd -- <entidad.json | carpeta/zip de paquete | pkg:id[@version]>
##        [--profile res://content/balance/reference_costs.json] [--mode free|regulated] [--budget id]
##        [--json | --md] [--library dir]
## Codigo de salida: 0 valido segun el modo, 2 no valido (modo reglamentado: presupuesto/no evaluable) o error tecnico.
## Los perfiles ilustrativos producen informes etiquetados como PRUEBA.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var profile_path := "res://content/balance/reference_costs.json"
	var mode := "free"
	var budget := ""
	var fmt := "md"
	var lib_dir := "user://library"
	var targets: Array[String] = []
	var i := 0
	while i < args.size():
		match args[i]:
			"--profile":
				profile_path = args[i + 1]
				i += 2
			"--mode":
				mode = args[i + 1]
				i += 2
			"--budget":
				budget = args[i + 1]
				i += 2
			"--library":
				lib_dir = args[i + 1]
				i += 2
			"--json":
				fmt = "json"
				i += 1
			"--md":
				fmt = "md"
				i += 1
			_:
				targets.append(args[i])
				i += 1
	if targets.is_empty():
		printerr("uso: balance_tool.gd -- <entidad.json|paquete|pkg:id> [--profile p] [--mode free|regulated] [--budget id] [--json|--md]")
		quit(2)
		return
	var prof := BalanceProfile.from_file(profile_path)
	var rules := Ruleset.from_file("res://content/rulesets/default_ruleset.json")
	var registry := OperationRegistry.new()
	var code := 0
	for t in targets:
		var data: Variant = null
		if t.begins_with("pkg:"):
			var spec := t.substr(4).split("@")
			var lib := ContentLibrary.new(lib_dir)
			var b := lib.build_entity(spec[0], spec[1] if spec.size() > 1 else "*", rules, prof, registry)
			data = b.get("data", null)
			if data == null:
				printerr("%s: %s" % [t, str(b["errors"])])
				code = 2
				continue
		elif DirAccess.dir_exists_absolute(t) or t.ends_with(".zip") or t.ends_with(".simpkg"):
			var imp := PackageImporter.new(ContentLibrary.new(lib_dir))
			var pk := PackageSource.read(t)
			var parsed := imp._parse_json_files(pk["files"], ImportReport.new())
			var man: Dictionary = parsed.get("manifest.json", {})
			var comp := EntityComposer.compose(parsed, man, imp.library, PackageSource.scripts_of(pk["files"]))
			if not comp["errors"].is_empty():
				printerr("%s: %s" % [t, str(comp["errors"])])
				code = 2
				continue
			data = comp["data"]
			(data as Dictionary)["id"] = str(man.get("id", "pkg"))
			(data as Dictionary)["team"] = "balance"
		else:
			data = EntityFactory.load_json(t)
		if not (data is Dictionary):
			printerr("no se pudo leer '%s'" % t)
			code = 2
			continue
		var r := BalanceEvaluator.evaluate(data, prof, rules, registry, {"mode": mode, "budget": budget})
		print(JSON.stringify(r.to_dict(), "  ") if fmt == "json" else r.to_markdown())
		if not r.valid():
			code = 2
	quit(code)
