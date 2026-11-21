extends SceneTree
## Micro-benchmark del motor (informativo; no es una prueba de aceptacion).
##   godot --headless --path . --script res://tools/bench.gd -- [N duelos] [full|reduced]

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var n := int(args[0]) if args.size() > 0 else 500
	var trace := args[1] if args.size() > 1 else "reduced"
	var cfg := {"trace": trace, "entities": [
		{"path": "res://content/fixtures/entities/attacker_a.json"},
		{"path": "res://content/fixtures/entities/attacker_b.json"}]}
	var t0 := Time.get_ticks_msec()
	var events := 0
	var wins := {"A": 0, "B": 0, "draw": 0}
	for i in n:
		cfg["seed"] = i + 1
		var out := DuelRunner.run(cfg)
		var r: CombatResult = out["result"]
		events += r.events
		wins[r.winner_team if r.is_win() else "draw"] += 1
	var dt := float(Time.get_ticks_msec() - t0) / 1000.0
	print("%d duelos (%s) en %.2f s: %.0f duelos/s, %.0f eventos/s, resultados=%s" % [n, trace, dt, n / dt, events / dt, str(wins)])
	quit(0)
