extends SceneTree
## Genera `content/conformance/expected.json` (valores de REFERENCIA del diagnostico de plataforma) en ESTA maquina.
## Usar SOLO en la plataforma de referencia y tras un cambio intencionado de motor/reglas (como tools/regen_golden.sh).
##   godot --headless --path . --script res://tools/gen_conformance.gd

func _init() -> void:
	var sc: Dictionary = EntityFactory.load_json(PlatformCheck.SCENARIOS)
	var pc := PlatformCheck.new({"skip_bench": true})
	pc._t_info()
	var duels := {}
	for s in sc["scenarios"]:
		var o := DuelRunner.run(pc._duel_config(s))
		if not bool(o["ok"]) or (o["result"] as CombatResult).is_aborted():
			printerr("escenario %s invalido: %s" % [s["id"], str(o["errors"])])
			quit(2)
			return
		duels[s["id"]] = PlatformCheck.duel_summary(o["result"])
	var out := {"schema": "simhalla.conformance_expected/1", "engine_version": CombatEngine.ENGINE_VERSION,
		"reference": {"os": pc.info["os"], "arch": pc.info["arch"], "godot": pc.info["godot"]},
		"math": PlatformCheck.math_vectors(), "libm_extra": PlatformCheck.libm_vectors(), "rng": PlatformCheck.rng_vectors(), "hashes": PlatformCheck.hash_vectors(),
		"formulas": PlatformCheck.formula_vectors(), "formats": PlatformCheck.format_vectors(), "examples": PlatformCheck.example_hashes(), "duels": duels}
	var f := FileAccess.open(PlatformCheck.EXPECTED, FileAccess.WRITE)
	f.store_string(JSON.stringify(out, "  ", true, true) + "\n")
	f.close()
	print("escrito %s (motor %s, referencia %s %s)" % [PlatformCheck.EXPECTED, CombatEngine.ENGINE_VERSION, pc.info["os"], pc.info["arch"]])
	quit()
