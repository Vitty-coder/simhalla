class_name CombatResult
extends RefCounted
## Resultado de un combate con metadatos de reproducibilidad.
##
## `outcome`: win | draw | aborted. ABORTED (error tecnico, limite de seguridad o
## cancelacion) nunca se cuenta como derrota ni empate: lleva `error`.
## `kind`: victory | limit | stalemate | technical | cancelled.

const WIN := "win"
const DRAW := "draw"
const ABORTED := "aborted"

var outcome: String = ""
var winner_team: String = ""
var reason: String = ""
var kind: String = ""
var error: Dictionary = {} ## {"code","message"} si outcome == aborted

var seed_value: int = 0
var engine_version: String = ""
var ruleset_id: String = ""
var ruleset_version: String = ""
var ruleset_hash: String = ""
var end_time: float = 0.0 ## unidades de tiempo virtual
var turns: int = 0
var actions: int = 0
var events: int = 0
var log_hash: String = ""
var entities: Dictionary = {} ## id -> {team, alive, hp}
var stats: Dictionary = {}
var metrics: Dictionary = {} ## metricas personalizadas definidas por contenido


func is_win() -> bool:
	return outcome == WIN


func is_draw() -> bool:
	return outcome == DRAW


func is_aborted() -> bool:
	return outcome == ABORTED


func to_dict() -> Dictionary:
	return {
		"outcome": outcome, "winner_team": winner_team, "reason": reason, "kind": kind,
		"error": error, "seed": seed_value, "engine_version": engine_version,
		"ruleset": {"id": ruleset_id, "version": ruleset_version, "hash": ruleset_hash},
		"end_time": end_time, "turns": turns, "actions": actions, "events": events,
		"log_hash": log_hash, "entities": entities, "stats": stats, "metrics": metrics,
	}
