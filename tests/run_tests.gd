extends SceneTree
## Ejecutor de pruebas headless.
##   godot --headless --path . --script res://tests/run_tests.gd [-- filtro]
## Busca tests/**/test_*.gd, instancia cada clase y ejecuta sus metodos test_*.
## Codigo de salida 0 = todo correcto, 1 = hay fallos.

const ROOTS := ["res://tests/unit", "res://tests/integration"]


func _init() -> void:
	TestCase.scene_tree = self
	var filter := ""
	var args := OS.get_cmdline_user_args()
	if args.size() > 0:
		filter = args[0]
	var files: Array[String] = []
	for root in ROOTS:
		_collect(root, files)
	files.sort()
	var total_cases := 0
	var total_asserts := 0
	var failed: Array[String] = []
	for path in files:
		if filter != "" and not path.contains(filter):
			continue
		var script: Variant = load(path)
		if script == null or not (script is GDScript) or not (script as GDScript).can_instantiate():
			failed.append("%s: no se pudo cargar/instanciar el script" % path)
			continue
		var inst: Variant = script.new()
		if not (inst is TestCase):
			failed.append("%s: no extiende TestCase" % path)
			continue
		var tc: TestCase = inst
		var methods: Array[String] = []
		for m in (script as GDScript).get_script_method_list():
			if str(m["name"]).begins_with("test_"):
				methods.append(str(m["name"]))
		methods.sort()
		var file_fail := 0
		for name in methods:
			tc._current = "%s::%s" % [path.get_file(), name]
			var before := tc.failures.size()
			tc.call(name)
			total_cases += 1
			if tc.failures.size() > before:
				file_fail += 1
		total_asserts += tc.assertions
		failed.append_array(tc.failures)
		print("%s %s  (%d casos)" % ["OK  " if file_fail == 0 else "FAIL", path.get_file(), methods.size()])
	print("")
	if failed.is_empty():
		print("TODAS LAS PRUEBAS OK: %d casos, %d aserciones" % [total_cases, total_asserts])
		quit(0)
	else:
		print("FALLOS (%d):" % failed.size())
		for f in failed:
			print("  - " + f)
		print("%d casos, %d aserciones" % [total_cases, total_asserts])
		quit(1)


func _collect(dir_path: String, out: Array[String]) -> void:
	var d := DirAccess.open(dir_path)
	if d == null:
		return
	for sub in d.get_directories():
		_collect(dir_path.path_join(sub), out)
	for f in d.get_files():
		if f.begins_with("test_") and f.ends_with(".gd"):
			out.append(dir_path.path_join(f))
