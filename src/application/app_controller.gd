class_name AppController
extends RefCounted
## Coordinador de la aplicacion (PROJECT.md §17.2: "la aplicacion coordina y la UI consume resultados"). Sin nodos ni escenas:
## posee el almacenamiento, la navegacion y los modelos de cada pantalla. La interfaz Godot (src/ui) solo presenta lo que estos
## modelos devuelven y les delega las acciones; NO ejecuta reglas de combate (las ejecuta el motor via SimulationSession/BatchRunner).

signal screen_changed(screen: String)
signal settings_changed

const SCREENS := ["library", "import", "duel", "viewer", "batch", "reports", "rules", "debug", "platform", "settings"]
const EXAMPLES := ["core_spells", "basic_ai", "ai_profiles", "arcane_duelist", "iron_vanguard", "rune_caster"]

var storage: AppStorage
var screen: String = "library"
var params: Dictionary = {}
var library: LibraryModel
var importer: ImportModel
var duel: DuelSetupModel
var viewer: ViewerModel = null
var batch: BatchModel
var reports: ReportsModel
var rules: RulesModel
var _stack: Array = []
var _registry: OperationRegistry = OperationRegistry.new()


func _init(root_dir: String = "user://simhalla") -> void:
	storage = AppStorage.new(root_dir)
	library = LibraryModel.new(self)
	importer = ImportModel.new(self)
	duel = DuelSetupModel.new(self)
	batch = BatchModel.new(self)
	reports = ReportsModel.new(self)
	rules = RulesModel.new(self)


## Prepara el almacenamiento (elementos incluidos) y aplica el idioma de los ajustes. Devuelve errores.
func boot() -> Array:
	var errs: Array = LocaleService.load_all()
	errs.append_array(storage.install_builtins())
	LocaleService.set_locale(str(storage.settings()["locale"]))
	return errs


# --- Ajustes y contexto de equilibrio ---------------------------------------------------------------------------------------

func settings() -> Dictionary:
	return storage.settings()


func save_settings(s: Dictionary) -> Array:
	var errs := storage.save_settings(s)
	if errs.is_empty():
		if s.has("locale"):
			LocaleService.set_locale(str(s["locale"]))
		settings_changed.emit()
	return errs


func mode() -> String:
	return str(settings()["default_mode"])


func budget() -> String:
	return str(settings()["default_budget"])


## Perfil de equilibrio activo (ajustes) o el tecnico si no se encuentra.
func profile(id: String = "") -> BalanceProfile:
	var pid := id if id != "" else str(settings()["default_profile"])
	var r := storage.profiles.latest(pid)
	if not r.is_empty():
		var g := storage.profiles.get_item(pid, str(r["version"]))
		if bool(g["ok"]):
			return BalanceProfile.from_dict(g["data"])
	return BalanceProfile.default_profile()


func ruleset(id: String = "builtin/default_ruleset", constraint: String = "*") -> Ruleset:
	var r := storage.rulesets.latest(id) if constraint == "*" else storage.rulesets.resolve(id, constraint)
	if not r.is_empty():
		var g := storage.rulesets.get_item(id, str(r["version"]))
		if bool(g["ok"]):
			return Ruleset.from_dict(g["data"])
	return Ruleset.from_file(AppStorage.BUILTIN_RULESET)


## Valoracion de PC de una entidad (dict) con el perfil/modo/presupuesto activos o los indicados en `opts`
## ({profile, mode, budget}). Devuelve BalanceReport.to_dict().
func cost_report(data: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var prof := profile(str(opts.get("profile", "")))
	var d: Dictionary = data.duplicate(true)
	if not d.has("id"):
		d["id"] = "entidad"
	if not d.has("team"):
		d["team"] = "x"
	return BalanceEvaluator.evaluate(d, prof, ruleset(), _registry, {"mode": str(opts.get("mode", mode())), "budget": str(opts.get("budget", budget()))}).to_dict()


# --- Ejemplos incluidos ----------------------------------------------------------------------------------------------------------

## Importa (idempotente) los paquetes de ejemplo que acompanan a la aplicacion, en orden de dependencias. Util en el primer arranque, sobre todo
## en moviles donde importar archivos es incomodo. {"installed": [...], "present": [...], "errors": [...]}
func install_examples() -> Dictionary:
	var out := {"installed": [], "present": [], "errors": []}
	for n in EXAMPLES:
		var rep := PackageImporter.new(storage.library, ruleset()).import_package("res://content/packages/" + n)
		if not rep.ok():
			out["errors"].append("%s: %s" % [n, "; ".join(rep.errors)])
		elif rep.already_present:
			out["present"].append("%s@%s" % [rep.id, rep.version])
		else:
			out["installed"].append("%s@%s" % [rep.id, rep.version])
			storage.log_event("install_example", "%s@%s" % [rep.id, rep.version], rep.hash)
	return out


# --- Navegacion ---------------------------------------------------------------------------------------------------------------

func go(target: String, p: Dictionary = {}) -> bool:
	if not SCREENS.has(target):
		return false
	if target != screen:
		_stack.append({"screen": screen, "params": params})
	screen = target
	params = p
	screen_changed.emit(screen)
	return true


func back() -> bool:
	if _stack.is_empty():
		return false
	var prev: Dictionary = _stack.pop_back()
	screen = prev["screen"]
	params = prev["params"]
	screen_changed.emit(screen)
	return true


## Etiqueta del modo para mostrarla siempre junto al coste (libre vs reglamentado).
func mode_label() -> String:
	return LocaleService.t("mode." + mode())


func can_go_back() -> bool:
	return not _stack.is_empty()
