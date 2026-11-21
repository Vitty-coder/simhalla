class_name TestCase
extends RefCounted
## Base minima de pruebas (sin dependencias externas, ejecutable headless).
## Cada metodo `test_*` de una subclase es un caso. Los helpers acumulan fallos.

## Arbol de escenas del ejecutor de pruebas (lo fija run_tests.gd): permite pruebas de interfaz con nodos reales.
static var scene_tree: SceneTree = null

var failures: Array[String] = []
var assertions: int = 0
var _current: String = ""


func fail(msg: String) -> void:
	failures.append("%s: %s" % [_current, msg])


func assert_true(cond: bool, msg: String = "se esperaba true") -> void:
	assertions += 1
	if not cond:
		fail(msg)


func assert_false(cond: bool, msg: String = "se esperaba false") -> void:
	assert_true(not cond, msg)


func assert_eq(actual: Variant, expected: Variant, msg: String = "") -> void:
	assertions += 1
	if typeof(actual) != typeof(expected) or actual != expected:
		fail("%s esperado=%s obtenido=%s" % [msg, str(expected), str(actual)])


func assert_ne(actual: Variant, other: Variant, msg: String = "") -> void:
	assertions += 1
	if typeof(actual) == typeof(other) and actual == other:
		fail("%s no deberian ser iguales: %s" % [msg, str(actual)])


func assert_almost(actual: float, expected: float, eps: float = 1e-9, msg: String = "") -> void:
	assertions += 1
	if absf(actual - expected) > eps:
		fail("%s esperado=%s obtenido=%s (eps=%s)" % [msg, str(expected), str(actual), str(eps)])


func assert_contains(haystack: Variant, needle: Variant, msg: String = "") -> void:
	assertions += 1
	var ok := false
	if haystack is String:
		ok = (haystack as String).contains(str(needle))
	elif haystack is Array or haystack is Dictionary:
		ok = needle in haystack
	if not ok:
		fail("%s no contiene %s en %s" % [msg, str(needle), str(haystack)])


# --- Utilidades de construccion para pruebas ---------------------------------------

## Entidad minima con estadisticas del perfil tecnico y overrides numericos.
static func make_entity(id: String, team: String, stat_overrides: Dictionary = {}, with_basic_attack: bool = true, rules: Ruleset = null) -> CombatEntity:
	var rs := rules if rules != null else Ruleset.from_dict({})
	var data := {"id": id, "team": team, "stats": stat_overrides, "basic_attack": with_basic_attack}
	var b := EntityFactory.build(data, BalanceProfile.default_profile(), rs, OperationRegistry.new())
	assert(b["errors"].is_empty(), str(b["errors"]))
	return b["entity"]


static func make_engine(entities: Array, seed_value: int = 1, rule_overrides: Dictionary = {}, trace: EventLog.TraceLevel = EventLog.TraceLevel.FULL, overrides: Dictionary = {}) -> CombatEngine:
	var eng := CombatEngine.new()
	var errs := eng.setup(Ruleset.from_dict(rule_overrides), entities, seed_value, trace, overrides)
	assert(errs.is_empty(), str(errs))
	return eng
