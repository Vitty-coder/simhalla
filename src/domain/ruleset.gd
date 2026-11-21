class_name Ruleset
extends RefCounted
## Reglamento global de combate (configurable y versionado).
##
## Define QUE ocurre en combate (ATB, formulas, limites). No es el perfil de
## equilibrio (ver BalanceProfile). Se carga desde JSON; las claves ausentes
## toman los valores por defecto de `default_data()`. Todos los valores marcados
## "provisional" en docs/DECISIONS.md son decisiones iniciales revisables.

## Techos tecnicos: ningun reglamento ni contenido puede superarlos.
const HARD_MAX_EVENTS := 5_000_000
const HARD_MAX_EVENT_DEPTH := 64
const HARD_MAX_ACTIONS_PER_TURN := 100
const HARD_MAX_REACTION_CHAIN := 8
const HARD_MAX_SCHEDULED := 10000
const HARD_MAX_ENTITIES := 256
const TIME_SCALE := 1_000_000 ## microunidades de tiempo/iniciativa por unidad.

const TIE_BREAK_CRITERIA := ["initiative_excess_desc", "spd_desc", "slot_asc", "random"]
const LIMIT_RESOLUTIONS := ["draw", "highest_hp_ratio"]
const SPD_POLICIES := ["clamp_zero"]
const ROLL_SCOPES := ["per_action", "per_component"]

var data: Dictionary = {}
var errors: Array[String] = []
var _path_cache: Dictionary = {}


static func default_data() -> Dictionary:
	return {
		"id": "default_ruleset",
		"version": "0.1.0-provisional",
		"atb": {
			"initiative_threshold": 1000.0,
			"tie_break": ["initiative_excess_desc", "spd_desc", "slot_asc"],
			"timed_events_first": true,
			"non_positive_spd": "clamp_zero",
		},
		"turn": {
			"main_actions_per_turn": 1,
			"max_actions_per_turn": 20,
		},
		"damage": {
			"rounding": {"mode": "round", "decimals": 0},
			"min_effective_defense": 0.0,
			"min_elemental_resistance": -1.0,
			"max_elemental_resistance": 1.0,
			"roll_scope": "per_action",
			"survive_hp": 1.0,
		},
		"hit": {
			"min_chance": 0.0,
			"max_chance": 1.0,
			"min_crit_chance": 0.0,
			"max_crit_chance": 1.0,
		},
		"basic_attack": {
			"id": "basic_attack",
			"name": "Ataque basico",
			"damage_type": "physical",
			"element": "",
			"formula": "caster.ATK",
			"can_crit": true,
		},
		"victory": {
			"simultaneous_death": "draw",
			"limits": {
				"max_virtual_time": 10000.0,
				"max_turns": 1000,
				"max_actions": 5000,
				"stagnation_turns": 50,
			},
			"limit_resolution": "draw",
		},
		"ai": {
			"failure_policy": "wait",
			"visible_fields": ["hp", "hp_max", "initiative", "resources", "statuses"],
		},
		"safety": {
			"max_events": 200000,
			"max_event_depth": 32,
			"max_reaction_chain": 4,
			"max_scheduled": 1000,
		},
		"scripting": {
			"max_instructions": 20000,
			"max_call_depth": 16,
			"max_collection": 256,
			"max_string": 256,
			"max_mutations": 32,
			"max_source_bytes": 16384,
			"max_ast_nodes": 3000,
		},
		"elements": ["fire", "water", "earth", "air", "lightning", "ice", "light", "dark"],
		"summons": {
			"max_per_owner": 8,
			"max_entities": 64,
			"on_owner_death": "despawn",
		},
	}


static func from_dict(overrides: Dictionary) -> Ruleset:
	var r := Ruleset.new()
	r.data = _merge(default_data(), overrides)
	r._validate()
	return r


static func from_file(path: String) -> Ruleset:
	var parsed: Variant = _read_json(path)
	if parsed == null or not (parsed is Dictionary):
		var r := Ruleset.new()
		r.data = default_data()
		r.errors.append("no se pudo leer un objeto JSON de '%s'" % path)
		return r
	return from_dict(parsed)


static func _read_json(path: String) -> Variant:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return null
	return JSON.parse_string(f.get_as_text())


static func _merge(base: Dictionary, over: Dictionary) -> Dictionary:
	var out: Dictionary = base.duplicate(true)
	for k in over:
		if out.has(k) and out[k] is Dictionary and over[k] is Dictionary:
			out[k] = _merge(out[k], over[k])
		else:
			out[k] = over[k]
	return out


func is_valid() -> bool:
	return errors.is_empty()


func get_path_value(path: String, default_value: Variant = null) -> Variant:
	# El reglamento es inmutable tras cargarse: se memoizan las rutas (la ruta se parte a cada consulta
	# en caliente: daño, impacto, limites). Los valores devueltos no deben modificarse.
	if _path_cache.has(path):
		return _path_cache[path]
	var found: Variant = _lookup(path, default_value)
	if found != default_value or default_value == null:
		_path_cache[path] = found
	return found


func _lookup(path: String, default_value: Variant) -> Variant:
	var cur: Variant = data
	for part in path.split("."):
		if cur is Dictionary and cur.has(part):
			cur = cur[part]
		else:
			return default_value
	return cur


# --- Accesores tipados de uso frecuente -------------------------------------

func id() -> String:
	return str(data.get("id", ""))


func version() -> String:
	return str(data.get("version", ""))


func threshold_micro() -> int:
	return int(round(float(get_path_value("atb.initiative_threshold")) * TIME_SCALE))


func tie_break() -> Array:
	return get_path_value("atb.tie_break")


func main_actions_per_turn() -> int:
	return int(get_path_value("turn.main_actions_per_turn"))


func max_actions_per_turn() -> int:
	return mini(int(get_path_value("turn.max_actions_per_turn")), HARD_MAX_ACTIONS_PER_TURN)


func rounding_mode() -> String:
	return str(get_path_value("damage.rounding.mode"))


func rounding_decimals() -> int:
	return int(get_path_value("damage.rounding.decimals"))


func round_value(v: float) -> float:
	return Rounding.apply(v, rounding_mode(), rounding_decimals())


func max_events() -> int:
	return mini(int(get_path_value("safety.max_events")), HARD_MAX_EVENTS)


func elements() -> Array:
	return get_path_value("elements", [])


func max_reaction_chain() -> int:
	return mini(int(get_path_value("safety.max_reaction_chain")), HARD_MAX_REACTION_CHAIN)


func max_scheduled() -> int:
	return mini(int(get_path_value("safety.max_scheduled")), HARD_MAX_SCHEDULED)


func max_entities() -> int:
	return mini(int(get_path_value("summons.max_entities")), HARD_MAX_ENTITIES)


func max_event_depth() -> int:
	return mini(int(get_path_value("safety.max_event_depth")), HARD_MAX_EVENT_DEPTH)


## Huella estable del contenido del reglamento (metadatos de reproducibilidad).
func content_hash() -> String:
	var ctx := HashingContext.new()
	ctx.start(HashingContext.HASH_SHA256)
	ctx.update(JSON.stringify(data, "", true, true).to_utf8_buffer())
	return ctx.finish().hex_encode()


# --- Validacion --------------------------------------------------------------

func _validate() -> void:
	errors.clear()
	if float(get_path_value("atb.initiative_threshold")) <= 0.0:
		errors.append("atb.initiative_threshold debe ser > 0")
	var tb: Variant = get_path_value("atb.tie_break")
	if not (tb is Array) or (tb as Array).is_empty():
		errors.append("atb.tie_break debe ser una lista no vacia")
	else:
		for c in tb:
			if not TIE_BREAK_CRITERIA.has(c):
				errors.append("atb.tie_break: criterio desconocido '%s'" % str(c))
	if not SPD_POLICIES.has(str(get_path_value("atb.non_positive_spd"))):
		errors.append("atb.non_positive_spd: politica no soportada")
	if int(get_path_value("turn.main_actions_per_turn")) < 0:
		errors.append("turn.main_actions_per_turn no puede ser negativo")
	if int(get_path_value("turn.max_actions_per_turn")) < 1:
		errors.append("turn.max_actions_per_turn debe ser >= 1")
	if not Rounding.MODES.has(rounding_mode()):
		errors.append("damage.rounding.mode desconocido '%s'" % rounding_mode())
	if rounding_decimals() < 0 or rounding_decimals() > 9:
		errors.append("damage.rounding.decimals debe estar entre 0 y 9")
	if float(get_path_value("damage.min_effective_defense")) <= -100.0:
		errors.append("damage.min_effective_defense debe ser > -100 (evita division por cero)")
	if float(get_path_value("damage.min_elemental_resistance")) > float(get_path_value("damage.max_elemental_resistance")):
		errors.append("damage.min_elemental_resistance no puede superar a max_elemental_resistance")
	if not ROLL_SCOPES.has(str(get_path_value("damage.roll_scope"))):
		errors.append("damage.roll_scope desconocido")
	if float(get_path_value("hit.min_chance")) > float(get_path_value("hit.max_chance")):
		errors.append("hit.min_chance no puede superar a hit.max_chance")
	if float(get_path_value("hit.min_crit_chance")) > float(get_path_value("hit.max_crit_chance")):
		errors.append("hit.min_crit_chance no puede superar a hit.max_crit_chance")
	if str(get_path_value("victory.simultaneous_death")) != "draw":
		errors.append("victory.simultaneous_death: solo 'draw' esta soportado")
	if not LIMIT_RESOLUTIONS.has(str(get_path_value("victory.limit_resolution"))):
		errors.append("victory.limit_resolution desconocido")
	for k in ["max_virtual_time", "max_turns", "max_actions", "stagnation_turns"]:
		if float(get_path_value("victory.limits.%s" % k, 0.0)) <= 0.0:
			errors.append("victory.limits.%s debe ser > 0" % k)
	if str(get_path_value("ai.failure_policy")) != "wait":
		errors.append("ai.failure_policy: solo 'wait' esta soportado")
	if int(get_path_value("safety.max_events")) < 1:
		errors.append("safety.max_events debe ser >= 1")
	if int(get_path_value("safety.max_event_depth")) < 1:
		errors.append("safety.max_event_depth debe ser >= 1")
	if int(get_path_value("safety.max_reaction_chain")) < 1:
		errors.append("safety.max_reaction_chain debe ser >= 1")
	if int(get_path_value("safety.max_scheduled")) < 1:
		errors.append("safety.max_scheduled debe ser >= 1")
	if int(get_path_value("summons.max_per_owner")) < 1 or int(get_path_value("summons.max_entities")) < 2:
		errors.append("summons.max_per_owner debe ser >= 1 y summons.max_entities >= 2")
	errors.append_array(ScriptLimits.validate_ruleset(self))
	var els: Variant = get_path_value("elements")
	if not (els is Array):
		errors.append("elements debe ser una lista de identificadores")
	else:
		var seen := {}
		for el in els:
			if not (el is String) or not RegEx.create_from_string("^[a-z][a-z0-9_]{0,31}$").search(str(el)):
				errors.append("elements: identificador invalido '%s'" % str(el))
			elif seen.has(el):
				errors.append("elements: '%s' duplicado" % str(el))
			seen[el] = true
	if not ["despawn", "stay"].has(str(get_path_value("summons.on_owner_death"))):
		errors.append("summons.on_owner_death debe ser despawn o stay")
	var ba: Variant = get_path_value("basic_attack")
	if ba is Dictionary:
		var f := Formula.parse(str(ba.get("formula", "")))
		if not f.is_valid():
			errors.append("basic_attack.formula invalida: %s" % f.error)
		if not ["physical", "magical", "true"].has(str(ba.get("damage_type", ""))):
			errors.append("basic_attack.damage_type invalido")
