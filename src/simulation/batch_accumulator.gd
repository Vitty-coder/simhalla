class_name BatchAccumulator
extends RefCounted
## Agregacion INCREMENTAL de resultados de un lote (minima, fase 7). Las estadisticas inferenciales
## (intervalos de Wilson, medianas, distribuciones, informes) pertenecen a la fase 8.
##
## Por escenario y por etiqueta de contendiente: victorias, derrotas, empates, abortos tecnicos (SEPARADOS: nunca
## cuentan como derrota ni empate), cancelados, errores de preparacion y trabajos pendientes. Denominadores explicitos:
##   n_finished = victorias + empates (combates resueltos)   n_errors = abortos tecnicos + errores de preparacion
## Medias (Welford) de turnos, tiempo virtual y eventos; dano/curacion medios por etiqueta.
## Las operaciones son conmutativas salvo la suma de flotantes: el resultado final se recalcula en ORDEN DE TRABAJO
## (`rebuild`) para que no dependa del orden de llegada ni del numero de workers.

var scenarios: Dictionary = {} ## key -> acumulado
var by_label: Dictionary = {} ## etiqueta -> {games, wins, losses, draws}
var totals := {"jobs": 0, "finished": 0, "wins": 0, "draws": 0, "aborted": 0, "cancelled": 0, "setup_errors": 0}


func _scen(key: String, label: String, sides: Dictionary) -> Dictionary:
	if not scenarios.has(key):
		scenarios[key] = {"key": key, "label": label, "sides": sides, "n_total": 0, "n_finished": 0, "n_errors": 0, "cancelled": 0,
			"wins_by_label": {}, "draws": 0, "aborted": 0, "setup_errors": 0,
			"turns": _m(), "end_time": _m(), "events": _m(), "damage_by_label": {}, "healing_by_label": {}, "errors": []}
	return scenarios[key]


static func _m() -> Dictionary:
	return {"n": 0, "mean": 0.0, "m2": 0.0, "min": 0.0, "max": 0.0}


static func _push(m: Dictionary, x: float) -> void:
	m["n"] = int(m["n"]) + 1
	var d: float = x - float(m["mean"])
	m["mean"] = float(m["mean"]) + d / float(m["n"])
	m["m2"] = float(m["m2"]) + d * (x - float(m["mean"]))
	m["min"] = x if int(m["n"]) == 1 else minf(float(m["min"]), x)
	m["max"] = x if int(m["n"]) == 1 else maxf(float(m["max"]), x)


static func variance(m: Dictionary) -> float:
	return float(m["m2"]) / float(int(m["n"]) - 1) if int(m["n"]) > 1 else 0.0


func _label_stat(label: String) -> Dictionary:
	if not by_label.has(label):
		by_label[label] = {"games": 0, "wins": 0, "losses": 0, "draws": 0}
	return by_label[label]


## Anade un registro de trabajo (ver BatchRunner). Los pendientes no se anaden.
func add(rec: Dictionary) -> void:
	var sc := _scen(str(rec["scenario"]), str(rec.get("scenario_label", rec["scenario"])), rec.get("sides", {}))
	totals["jobs"] += 1
	sc["n_total"] += 1
	var status := str(rec["status"])
	if status == "cancelled":
		totals["cancelled"] += 1
		sc["cancelled"] += 1
		return
	if status == "setup_error":
		totals["setup_errors"] += 1
		sc["setup_errors"] += 1
		sc["n_errors"] += 1
		if sc["errors"].size() < 5:
			sc["errors"].append(str(rec.get("error", "")))
		return
	if status == "aborted":
		totals["aborted"] += 1
		sc["aborted"] += 1
		sc["n_errors"] += 1
		if sc["errors"].size() < 5:
			sc["errors"].append(str(rec.get("error", "")))
		return
	# resuelto: win | draw
	totals["finished"] += 1
	sc["n_finished"] += 1
	var sides: Dictionary = rec.get("sides", {})
	for team in sides:
		_label_stat(str(sides[team]))["games"] += 1
	if status == "win":
		totals["wins"] += 1
		var winner: String = str(sides.get(str(rec["winner_team"]), rec["winner_team"]))
		sc["wins_by_label"][winner] = int(sc["wins_by_label"].get(winner, 0)) + 1
		_label_stat(winner)["wins"] += 1
		for team in sides:
			if str(team) != str(rec["winner_team"]):
				_label_stat(str(sides[team]))["losses"] += 1
	else:
		totals["draws"] += 1
		sc["draws"] += 1
		for team in sides:
			_label_stat(str(sides[team]))["draws"] += 1
	_push(sc["turns"], float(rec["turns"]))
	_push(sc["end_time"], float(rec["end_time"]))
	_push(sc["events"], float(rec["events"]))
	var per: Dictionary = rec.get("sides_stats", {})
	for team in per:
		var lbl := str(sides.get(team, team))
		sc["damage_by_label"][lbl] = float(sc["damage_by_label"].get(lbl, 0.0)) + float(per[team]["damage_dealt"])
		sc["healing_by_label"][lbl] = float(sc["healing_by_label"].get(lbl, 0.0)) + float(per[team]["healing_done"])


func summary() -> Dictionary:
	var out := {"totals": totals.duplicate(), "scenarios": [], "by_label": by_label.duplicate(true)}
	var keys: Array = scenarios.keys()
	keys.sort()
	for k in keys:
		var s: Dictionary = scenarios[k].duplicate(true)
		var n: int = s["n_finished"]
		s["denominator"] = n
		s["win_rates"] = {}
		for l in s["wins_by_label"]:
			s["win_rates"][l] = float(s["wins_by_label"][l]) / float(n) if n > 0 else 0.0
		s["draw_rate"] = float(s["draws"]) / float(n) if n > 0 else 0.0
		for m in ["turns", "end_time", "events"]:
			s[m]["variance"] = variance(s[m])
		s["damage_mean_by_label"] = {}
		s["healing_mean_by_label"] = {}
		for l in s["damage_by_label"]:
			s["damage_mean_by_label"][l] = float(s["damage_by_label"][l]) / float(n) if n > 0 else 0.0
			s["healing_mean_by_label"][l] = float(s["healing_by_label"].get(l, 0.0)) / float(n) if n > 0 else 0.0
		out["scenarios"].append(s)
	return out


## Reconstruye desde cero en orden de trabajo (resultado independiente del orden de llegada).
static func rebuild(records: Array) -> BatchAccumulator:
	var a := BatchAccumulator.new()
	for r in records:
		if r != null:
			a.add(r)
	return a
