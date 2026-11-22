extends SceneTree
## Comprueba un paquete de personaje: valida/importa, valora costes y lo enfrenta a oponentes de serie. Para quien crea contenido.
##   godot --headless --path . --script res://tools/character_check.gd -- <carpeta|zip del paquete>
##        [--deps <ruta> ...] [--vs pkg:id ...] [--reps 10] [--seed 1] [--budget standard] [--profile builtin/reference_costs] [--json]
## No modifica la biblioteca del usuario (usa una temporal). Codigo de salida: 0 = valido, 2 = rechazado o error tecnico.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var path := ""
	var opts := {"deps": [], "vs": []}
	var as_json := false
	var i := 0
	while i < args.size():
		match args[i]:
			"--deps":
				opts["deps"].append(args[i + 1])
				i += 2
			"--vs":
				opts["vs"].append(args[i + 1])
				i += 2
			"--reps":
				opts["reps"] = int(args[i + 1])
				i += 2
			"--seed":
				opts["seed"] = int(args[i + 1])
				i += 2
			"--budget":
				opts["budget"] = args[i + 1]
				i += 2
			"--profile":
				opts["profile"] = args[i + 1]
				i += 2
			"--json":
				as_json = true
				i += 1
			_:
				path = args[i]
				i += 1
	if path == "":
		printerr("uso: character_check.gd -- <paquete> [--deps ruta] [--vs pkg:id] [--reps N] [--seed N] [--budget id] [--profile id] [--json]")
		quit(2)
		return
	var r := CharacterCheck.run(path, opts)
	print(JSON.stringify(r, "  ") if as_json else CharacterCheck.to_markdown(r))
	quit(0 if bool(r["ok"]) else 2)
