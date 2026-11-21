class_name LastTeamStanding
extends VictoryCondition
## Victoria estandar: queda vivo (y contando para la victoria) un unico equipo.
## Si no queda ninguno (muerte simultanea): empate segun el reglamento.

func evaluate(engine: CombatEngine, point: String) -> Dictionary:
	if point != "after_action":
		return {}
	var alive_teams := {}
	for e in engine.entities:
		var ent: CombatEntity = e
		if ent.alive and ent.counts_for_victory:
			alive_teams[ent.team] = true
	if alive_teams.size() == 1:
		return {"outcome": CombatResult.WIN, "winner_team": str(alive_teams.keys()[0]), "reason": "last_team_standing", "kind": "victory"}
	if alive_teams.is_empty():
		return {"outcome": CombatResult.DRAW, "winner_team": "", "reason": "simultaneous_death", "kind": "victory"}
	return {}
