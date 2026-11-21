class_name LimitCondition
extends VictoryCondition
## Limites de combate del reglamento: turnos, acciones y estancamiento.
## (El limite de tiempo virtual lo aplica el motor al planificar.)
## Al alcanzarse se aplica `victory.limit_resolution`: empate, o gana el equipo
## con mayor fraccion de vida restante (empate exacto = empate).
## Es un FINAL REGLAMENTARIO, distinto de un aborto tecnico por error.

func evaluate(engine: CombatEngine, point: String) -> Dictionary:
	if point == "after_action":
		return {}
	var rules := engine.rules
	var reason := ""
	if engine.turn_count >= int(rules.get_path_value("victory.limits.max_turns")) and point == "turn_boundary":
		reason = "max_turns"
	elif engine.action_count >= int(rules.get_path_value("victory.limits.max_actions")):
		reason = "max_actions"
	elif point == "turn_boundary" and engine.turn_count - engine.last_hp_change_turn >= int(rules.get_path_value("victory.limits.stagnation_turns")):
		reason = "stagnation"
	if reason == "":
		return {}
	return resolve_limit(engine, reason)


static func resolve_limit(engine: CombatEngine, reason: String) -> Dictionary:
	var res := {"outcome": CombatResult.DRAW, "winner_team": "", "reason": reason, "kind": "limit"}
	if str(engine.rules.get_path_value("victory.limit_resolution")) == "highest_hp_ratio":
		var hp := {}
		var mx := {}
		for e in engine.entities:
			var ent: CombatEntity = e
			if not ent.counts_for_victory:
				continue
			hp[ent.team] = float(hp.get(ent.team, 0.0)) + ent.hp
			mx[ent.team] = float(mx.get(ent.team, 0.0)) + ent.hp_max()
		var best_team := ""
		var best := -1.0
		var tie := false
		var teams: Array = hp.keys()
		teams.sort()
		for t in teams:
			var ratio: float = float(hp[t]) / maxf(float(mx[t]), 1e-9)
			if absf(ratio - best) <= 1e-9:
				tie = true
			elif ratio > best:
				best = ratio
				best_team = t
				tie = false
		if not tie and best_team != "":
			res["outcome"] = CombatResult.WIN
			res["winner_team"] = best_team
	return res
