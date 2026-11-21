extends SceneTree
## CLI de duelos headless.
##   godot --headless --path . --script res://tools/run_duel.gd -- A.json B.json [semilla] [--log] [--json] [--library dir]
## Entidades: fichero JSON o paquete importado `pkg:ns/nombre[@restriccion]` (p. ej. pkg:examples/iron_vanguard@^1.0.0).
## Rutas relativas a res://content/fixtures/entities/ si no empiezan por res:// .

const FIX := "res://content/fixtures/entities/"


func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var paths: Array[String] = []
	var seed_value := 1
	var show_log := false
	var as_json := false
	var library := "user://library"
	var skip := false
	for ai in args.size():
		if skip:
			skip = false
			continue
		var a: String = args[ai]
		if a == "--library" and ai + 1 < args.size():
			library = args[ai + 1]
			skip = true
		elif a == "--log":
			show_log = true
		elif a == "--json":
			as_json = true
		elif a.is_valid_int():
			seed_value = int(a)
		else:
			paths.append(a if (a.begins_with("res://") or a.begins_with("pkg:")) else FIX + a)
	if paths.size() < 2:
		printerr("uso: run_duel.gd -- A.json B.json [semilla] [--log] [--json]")
		quit(2)
		return
	var specs: Array = []
	for p in paths:
		if p.begins_with("pkg:"):
			var parts := p.substr(4).split("@")
			specs.append({"package": parts[0], "version": parts[1] if parts.size() > 1 else "*", "overrides": {"team": "T%d" % specs.size()}})
		else:
			specs.append({"path": p})
	var out := DuelRunner.run({"seed": seed_value, "entities": specs, "library": library})
	if not out["ok"]:
		printerr("ERRORES:\n  " + "\n  ".join(out["errors"]))
		quit(2)
		return
	var r: CombatResult = out["result"]
	if as_json:
		print(JSON.stringify(r.to_dict(), "  ", true))
	else:
		if show_log:
			for ev in (out["engine"] as CombatEngine).log.events:
				if ["time_advanced", "action_selected"].has(ev["type"]):
					continue
				print("[t=%8.3f #%-4d] %-18s %s -> %s %s" % [float(ev["time"]) / Ruleset.TIME_SCALE, ev["id"], ev["type"], ev["source"], ev["target"], JSON.stringify(ev["data"], "", true)])
		print("resultado: %s ganador=%s motivo=%s turnos=%d acciones=%d eventos=%d t=%.3f" % [r.outcome, r.winner_team, r.reason, r.turns, r.actions, r.events, r.end_time])
		print("huella: " + r.log_hash)
	quit(0 if not r.is_aborted() else 1)
