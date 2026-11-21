class_name ScriptApi
extends RefCounted
## Catalogo VERSIONADO y de lista permitida de las funciones que un script puede llamar.
## Un script no puede llamar nada que no este aqui (se comprueba al compilar/enlazar,
## antes de ejecutar nunca). Los valores que cruzan la frontera son solo datos
## (numero, texto, booleano, null, lista, mapa): jamas objetos del motor ni de Godot.
##
## Contextos: "effect" (operacion `script` de una habilidad) y "ai" (IA `script`).
## kind: pure (sin estado) | query (lee estado autorizado) | mutate (cambia el combate por el
## motor: validado y con eventos) | rng (flujo "script" del RNG del motor) | state (variables del script).

const VERSION := 1

const EFFECT := "effect"
const AI := "ai"
const BOTH := ["effect", "ai"]

## nombre -> [min_args, max_args, kind, contextos]
const CATALOG := {
	# --- puras (ambos contextos) ---
	"abs": [1, 1, "pure", BOTH], "min": [2, 2, "pure", BOTH], "max": [2, 2, "pure", BOTH],
	"floor": [1, 1, "pure", BOTH], "ceil": [1, 1, "pure", BOTH], "round": [1, 1, "pure", BOTH],
	"sqrt": [1, 1, "pure", BOTH], "clamp": [3, 3, "pure", BOTH], "len": [1, 1, "pure", BOTH],
	"str": [1, 1, "pure", BOTH], "num": [1, 1, "pure", BOTH], "push": [2, 2, "pure", BOTH],
	"pop": [1, 1, "pure", BOTH], "keys": [1, 1, "pure", BOTH], "has": [2, 2, "pure", BOTH],
	"sort": [1, 1, "pure", BOTH], "sum": [1, 1, "pure", BOTH], "type": [1, 1, "pure", BOTH],
	"concat": [2, 2, "pure", BOTH],
	# --- consultas de estado autorizado (efectos) ---
	"stat": [2, 2, "query", [EFFECT]], "hp": [1, 1, "query", [EFFECT]], "hp_max": [1, 1, "query", [EFFECT]],
	"hp_ratio": [1, 1, "query", [EFFECT]], "res": [2, 2, "query", [EFFECT]], "res_max": [2, 2, "query", [EFFECT]],
	"alive": [1, 1, "query", [EFFECT]], "team": [1, 1, "query", [EFFECT]], "is_enemy": [2, 2, "query", [EFFECT]],
	"enemies": [1, 1, "query", [EFFECT]], "allies": [1, 1, "query", [EFFECT]],
	"status_stacks": [2, 2, "query", [EFFECT]], "has_tag": [2, 2, "query", [EFFECT]],
	"turn": [0, 0, "query", [EFFECT]], "time": [0, 0, "query", [EFFECT]], "get_var": [1, 1, "state", [EFFECT]],
	# --- operaciones de combate (efectos): validadas y con eventos ---
	"deal_damage": [2, 3, "mutate", [EFFECT]], "heal": [2, 2, "mutate", [EFFECT]],
	"modify_resource": [3, 3, "mutate", [EFFECT]], "apply_status": [2, 3, "mutate", [EFFECT]],
	"remove_status": [2, 2, "mutate", [EFFECT]], "emit": [1, 2, "mutate", [EFFECT]],
	"metric": [2, 2, "mutate", [EFFECT]], "attack_roll": [1, 1, "mutate", [EFFECT]],
	"set_var": [2, 2, "state", [EFFECT]],
	# --- RNG propio del motor (solo efectos: la IA no consume tiradas reales) ---
	"rand": [0, 0, "rng", [EFFECT]], "rand_int": [1, 1, "rng", [EFFECT]], "chance": [1, 1, "rng", [EFFECT]],
	# --- prediccion sobre la vista (IA) ---
	"predict": [3, 3, "query", [AI]], "observed_ratio": [4, 4, "query", [AI]],
}

const RESERVED := ["fn", "let", "const", "if", "else", "while", "for", "in", "return", "break", "continue", "true", "false", "null", "and", "or", "not", "range"]


static func has_function(name: String) -> bool:
	return CATALOG.has(name)


static func allowed_in(name: String, context: String) -> bool:
	return CATALOG.has(name) and (CATALOG[name][3] as Array).has(context)


static func arity(name: String) -> Array:
	return [CATALOG[name][0], CATALOG[name][1]]


static func kind_of(name: String) -> String:
	return CATALOG[name][2]


static func is_pure(name: String) -> bool:
	return CATALOG.has(name) and CATALOG[name][2] == "pure"
