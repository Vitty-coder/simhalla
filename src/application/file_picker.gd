class_name FilePicker
extends RefCounted
## Seleccion de archivos para importar, con tres estrategias segun la plataforma (PROJECT.md §17.1: PC y Android, offline):
##   native  dialogo nativo del sistema (`DisplayServer.file_dialog_show`) si el sistema lo soporta (en Android abre el selector del sistema)
##   dialog  `FileDialog` de Godot (escritorio)
##   inbox   «bandeja de entrada» `user://simhalla/inbox`: carpeta de la aplicacion donde se dejan paquetes (.zip/.simpkg/.simbundle/carpetas/.json)
##           con el gestor de archivos o `adb push`; es la via GARANTIZADA sin permisos de almacenamiento (en Android `user://` es privado).
## La logica pura (clasificar, listar la bandeja, copiar a ella, elegir estrategia) es independiente de la interfaz y esta probada en headless;
## los dialogos nativos solo pueden verificarse en el dispositivo.

const EXTENSIONS := ["zip", "simpkg", "simbundle", "json"]


static func inbox_dir(storage_root: String) -> String:
	return storage_root.path_join("inbox")


static func ensure_inbox(storage_root: String) -> String:
	DirAccess.make_dir_recursive_absolute(inbox_dir(storage_root))
	return inbox_dir(storage_root)


## "package" (carpeta con manifest.json o .zip/.simpkg), "bundle" (.simbundle), "json" o "unknown".
static func classify(path: String) -> String:
	if DirAccess.dir_exists_absolute(path):
		return "package" if FileAccess.file_exists(path.path_join("manifest.json")) else "unknown"
	match path.get_extension().to_lower():
		"zip", "simpkg":
			return "package"
		"simbundle":
			return "bundle"
		"json":
			return "json"
	return "unknown"


## [{name, path, kind}] de la bandeja de entrada (orden alfabetico; ignora lo que no es importable).
static func list_inbox(storage_root: String) -> Array:
	var dir := ensure_inbox(storage_root)
	var out: Array = []
	var d := DirAccess.open(dir)
	if d == null:
		return out
	var names: Array = []
	for x in d.get_directories():
		names.append(str(x))
	for x in d.get_files():
		names.append(str(x))
	names.sort()
	for n in names:
		var p := dir.path_join(n)
		var k := classify(p)
		if k != "unknown":
			out.append({"name": n, "path": p, "kind": k})
	return out


## Copia un archivo (no carpeta) a la bandeja. {"ok","path","error"}.
static func copy_into_inbox(src: String, storage_root: String) -> Dictionary:
	if not FileAccess.file_exists(src):
		return {"ok": false, "path": "", "error": "[no_encontrado] %s" % src}
	if classify(src) == "unknown":
		return {"ok": false, "path": "", "error": "[formato] solo se admiten %s" % ", ".join(EXTENSIONS)}
	var dest := ensure_inbox(storage_root).path_join(src.get_file())
	var err := DirAccess.copy_absolute(src, dest)
	return {"ok": err == OK, "path": dest, "error": "" if err == OK else "[escritura] no se pudo copiar (%d)" % err}


## Estrategia segun la plataforma. Los parametros permiten simular otras plataformas en las pruebas.
static func strategy(native_dialog: Variant = null, mobile: Variant = null) -> String:
	var nat: bool = DisplayServer.has_feature(DisplayServer.FEATURE_NATIVE_DIALOG_FILE) if native_dialog == null else bool(native_dialog)
	var mob: bool = OS.has_feature("mobile") if mobile == null else bool(mobile)
	if nat:
		return "native"
	return "inbox" if mob else "dialog"


## Abre el selector. `on_picked(path)` se invoca con la ruta elegida. Devuelve la estrategia usada ("inbox" = no hay dialogo: usar la bandeja).
static func open(parent: Node, on_picked: Callable, strat: String = "") -> String:
	var s := strat if strat != "" else strategy()
	match s:
		"native":
			var filters := PackedStringArray(["*.zip,*.simpkg,*.simbundle,*.json ; Simhalla"])
			DisplayServer.file_dialog_show("Simhalla", "", "", false, DisplayServer.FILE_DIALOG_MODE_OPEN_ANY, filters, func(ok: bool, paths: PackedStringArray, _idx: int):
				if ok and not paths.is_empty():
					on_picked.call(paths[0]))
		"dialog":
			var dlg := FileDialog.new()
			dlg.access = FileDialog.ACCESS_FILESYSTEM
			dlg.file_mode = FileDialog.FILE_MODE_OPEN_ANY
			dlg.use_native_dialog = false
			dlg.filters = PackedStringArray(["*.zip, *.simpkg, *.simbundle, *.json ; Simhalla"])
			dlg.min_size = Vector2i(640, 420)
			dlg.file_selected.connect(func(p: String): on_picked.call(p); dlg.queue_free())
			dlg.dir_selected.connect(func(p: String): on_picked.call(p); dlg.queue_free())
			dlg.canceled.connect(func(): dlg.queue_free())
			parent.add_child(dlg)
			dlg.popup_centered()
	return s
