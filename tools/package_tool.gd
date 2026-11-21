extends SceneTree
## Gestion de paquetes de contenido.
##   godot --headless --path . --script res://tools/package_tool.gd -- validate <ruta>
##   godot --headless --path . --script res://tools/package_tool.gd -- import <ruta> [<ruta>...]
##   godot --headless --path . --script res://tools/package_tool.gd -- list
## Opcion: --library <dir> (por defecto user://library). Codigo de salida 0 = OK, 2 = rechazado.

func _init() -> void:
	var args := OS.get_cmdline_user_args()
	var lib_dir := "user://library"
	var rest: Array[String] = []
	var i := 0
	while i < args.size():
		if args[i] == "--library" and i + 1 < args.size():
			lib_dir = args[i + 1]
			i += 2
		else:
			rest.append(args[i])
			i += 1
	if rest.is_empty():
		printerr("uso: package_tool.gd -- validate|import|list [rutas] [--library dir]")
		quit(2)
		return
	var lib := ContentLibrary.new(lib_dir)
	var imp := PackageImporter.new(lib)
	var code := 0
	match rest[0]:
		"list":
			for e in lib.list():
				print("%s@%s  %s  %s" % [e["id"], e["version"], e["type"], str(e["hash"]).substr(0, 12)])
		"validate", "import":
			for p in rest.slice(1):
				var rep := imp.import_package(p) if rest[0] == "import" else imp.validate(p)
				print("%s: %s" % [p, rep.summary()])
				for w in rep.warnings:
					print("  aviso: " + w)
				if not rep.ok():
					code = 2
		_:
			printerr("orden desconocida '%s'" % rest[0])
			code = 2
	quit(code)
