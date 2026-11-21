extends SceneTree
## Calibracion empirica de costes: valora y enfrenta a los contendientes y propone un perfil con multiplicadores por categoria (ILUSTRATIVO).
##   godot --headless --path . --script res://tools/calibrate_tool.gd -- <entidad.json | pkg:id[@version]> ... (>= 4)
##        [--profile res://content/balance/reference_costs.json] [--reps 10] [--seed 1] [--workers 0] [--library dir]
##        [--out propuesta.json] [--json]
## Salida: informe Markdown (o JSON con --json). Codigo 0 = calibrado; 2 = error o datos insuficientes. La propuesta NO se aplica sola.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var profile_path := "res://content/balance/reference_costs.json"
	var lib_dir := "user://library"
	var out_path := ""
	var reps := 10
	var seed_value := 1
	var workers := 0
	var as_json := false
	var targets: Array[String] = []
	var i := 0
	while i < args.size():
		match args[i]:
			"--profile":
				profile_path = args[i + 1]
				i += 2
			"--library":
				lib_dir = args[i + 1]
				i += 2
			"--out":
				out_path = args[i + 1]
				i += 2
			"--reps":
				reps = int(args[i + 1])
				i += 2
			"--seed":
				seed_value = int(args[i + 1])
				i += 2
			"--workers":
				workers = int(args[i + 1])
				i += 2
			"--json":
				as_json = true
				i += 1
			_:
				targets.append(args[i])
				i += 1
	var prof := BalanceProfile.from_file(profile_path)
	var rules := Ruleset.from_file("res://content/rulesets/default_ruleset.json")
	var reg := OperationRegistry.new()
	var contestants: Array = []
	for t in targets:
		if t.begins_with("pkg:"):
			var spec := t.substr(4).split("@")
			var lib := ContentLibrary.new(lib_dir)
			var b := lib.build_entity(spec[0], spec[1] if spec.size() > 1 else "*", rules, prof, reg)
			if b.get("data", null) == null:
				printerr("%s: %s" % [t, str(b["errors"])])
				quit(2)
				return
			contestants.append({"label": spec[0], "spec": {"package": spec[0], "version": spec[1] if spec.size() > 1 else ""}, "data": b["data"]})
		else:
			var d: Variant = EntityFactory.load_json(t)
			if not (d is Dictionary):
				printerr("%s: no se pudo leer" % t)
				quit(2)
				return
			contestants.append({"label": t.get_file().get_basename(), "spec": {"path": t}, "data": d})
	var r := BalanceCalibrator.calibrate(contestants, prof, rules, reg, {"reps": reps, "master_seed": seed_value, "workers": workers,
		"base": {"library": lib_dir, "ruleset_data": rules.data, "profile_data": prof.to_dict(), "ruleset_overrides": {"victory": {"limits": {"max_turns": 60, "stagnation_turns": 30}}}}})
	print(JSON.stringify(r, "  ") if as_json else BalanceCalibrator.to_markdown(r))
	if out_path != "" and r.get("suggested_profile", null) is Dictionary:
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(JSON.stringify(r["suggested_profile"], "  "))
			f.close()
	quit(0 if bool(r.get("ok", false)) else 2)
