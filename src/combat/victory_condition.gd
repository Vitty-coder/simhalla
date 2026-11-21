class_name VictoryCondition
extends RefCounted
## Condicion de finalizacion evaluable por el motor.
##
## `point`: "after_action" (tras resolver una accion/evento temporizado: punto
## seguro, ya resueltas muertes y reacciones), "turn_boundary" (al empezar a
## buscar el siguiente turno) o "pre_decision" (antes de pedir una decision).
## Devuelve {} si no termina, o {"outcome","winner_team","reason","kind"}.
## Las condiciones alternativas definidas por mecanicas de PJ (fase 5) se anaden
## como nuevas subclases/entradas de `engine.end_conditions`.

func evaluate(_engine: CombatEngine, _point: String) -> Dictionary:
	return {}
