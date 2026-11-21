class_name BatchReport
extends RefCounted
## Informe MASIVO (PROJECT.md §13/§14.2): modelo estructurado y versionado (`simhalla.report/1`, kind `batch`) calculado
## SOLO a partir de los registros del lote (en orden de trabajo), de modo que es reproducible: el mismo lote da el mismo
## informe, con 1 o N workers. Muestra siempre el tamano de muestra, los denominadores y la configuracion del lote.
##
## Por escenario: resultados (victorias/empates con intervalos de Wilson 95 %), errores aparte, distribuciones (turnos, tiempo,
## eventos: media con IC t, mediana, cuartiles, histograma), dano/curacion medios, eficacia de habilidades (ASOCIACION
## observada, no causalidad), metricas de contenido y semillas para reproducir. Global: comparaciones (emparejadas si procede,
## Newcombe si son independientes), matriz de enfrentamientos favorables/desfavorables, clasificacion por contendiente y notas
## metodologicas (`Stats`). El rendimiento (`measurement`) va aparte y NO entra en la huella del informe.
##
## options: {"bins": 10, "max_errors": 5}

const SCHEMA := "simhalla.report/1"
const METHODS := {
	"rates": "Tasas (victorias, empates, uso de habilidades): intervalo binomial de Wilson al 95 %.",
	"means": "Medias: intervalo t de Student al 95 % (valores criticos tabulados; normal para df > 120). Mediana y cuartiles: cuantiles de tipo 7.",
	"diff_independent": "Diferencia de tasas independientes: intervalo de Newcombe (hibrido de puntuacion).",
	"diff_paired": "Comparacion emparejada (misma semilla en ambas variantes): diferencias por pareja con IC t y recuento de parejas discordantes.",
	"abilities": "La eficacia de habilidades es una ASOCIACION observada (tasa de victoria cuando se usa vs cuando no): no demuestra que la habilidad cause la victoria.",
	"caveat": "Los intervalos son aproximados y anchos con muestras pequenas; mire siempre n. Igualdad de resultados no implica igualdad de poder ni de coste de creacion.",
}


static func build(res: BatchResult, options: Dictionary = {}) -> Dictionary:
	var bins := int(options.get("bins", 10))
	var max_err := int(options.get("max_errors", 5))
	var plan: Dictionary = res.plan
	var recs: Array = res.records.filter(func(r): return r != null)
	var scen_meta: Dictionary = {}
	for s in plan.get("scenarios", []):
		scen_meta[str(s["key"])] = s
	var m := {"schema": SCHEMA, "kind": "batch"}
	m["meta"] = {
		"name": plan.get("name", ""), "master_seed": str(plan.get("master_seed", 0)), "seed_mode": plan.get("seed_mode", ""), "repetitions": plan.get("repetitions", 0),
		"engine_version": res.engine_version, "plan_fingerprint": res.plan_fingerprint, "fingerprint": res.fingerprint, "status": res.status,
		"base": plan.get("base", {}), "contents": res.contents,
		"scenarios": (plan.get("scenarios", []) as Array).map(func(s): return {"key": s["key"], "label": s.get("label", s["key"]), "params": s.get("params", {}),
			"sides": s.get("sides", {}), "group": s.get("group", ""), "repetitions": s.get("repetitions", plan.get("repetitions", 1)), "ruleset_overrides": s.get("ruleset_overrides", {})}),
		"reproduce": "BatchRunner.replay(plan, indice) con el plan guardado reproduce cada duelo; la semilla de cada trabajo se deriva de la maestra (ver `jobs`)",
	}
	m["sample"] = {"total_jobs": res.total_jobs, "executed": res.executed, "pending": res.pending(), "finished": 0, "errors": 0, "cancelled": 0}
	var by_scen: Dictionary = {}
	for r in recs:
		var k := str(r["scenario"])
		if not by_scen.has(k):
			by_scen[k] = []
		by_scen[k].append(r)
	var keys: Array = by_scen.keys()
	keys.sort()
	var scenarios: Array = []
	for k in keys:
		scenarios.append(_scenario(k, by_scen[k], scen_meta.get(k, {}), bins, max_err))
	m["scenarios"] = scenarios
	for s in scenarios:
		m["sample"]["finished"] += int(s["sample"]["finished"])
		m["sample"]["errors"] += int(s["sample"]["errors"])
		m["sample"]["cancelled"] += int(s["sample"]["cancelled"])
	m["ranking"] = _ranking(recs)
	m["matrix"] = _matrix(recs)
	m["comparisons"] = _comparisons(by_scen, scen_meta, plan)
	m["methods"] = METHODS
	m["measurement"] = {"note": "rendimiento medido: NO reproducible, fuera de la huella del informe", "perf": res.perf}
	return m


static func _label_of(rec: Dictionary, team: String) -> String:
	return str((rec.get("sides", {}) as Dictionary).get(team, team))


static func _rate(k: int, n: int) -> Dictionary:
	return {"k": k, "n": n, "rate": float(k) / float(n) if n > 0 else null, "wilson95": Stats.wilson(k, n)}


static func _scenario(key: String, recs: Array, meta: Dictionary, bins: int, max_err: int) -> Dictionary:
	var finished: Array = recs.filter(func(r): return r["status"] == "win" or r["status"] == "draw")
	var aborted: Array = recs.filter(func(r): return r["status"] == "aborted")
	var setup: Array = recs.filter(func(r): return r["status"] == "setup_error")
	var cancelled: Array = recs.filter(func(r): return r["status"] == "cancelled")
	var n := finished.size()
	var out := {"key": key, "label": meta.get("label", key), "params": meta.get("params", {}), "sides": meta.get("sides", {})}
	out["sample"] = {"n_total": recs.size(), "finished": n, "denominator": n, "aborted": aborted.size(), "setup_errors": setup.size(), "errors": aborted.size() + setup.size(), "cancelled": cancelled.size()}
	# resultados
	var labels: Array = []
	for t in (meta.get("sides", {}) as Dictionary):
		if not labels.has(str(meta["sides"][t])):
			labels.append(str(meta["sides"][t]))
	labels.sort()
	var wins := {}
	var draws := 0
	for r in finished:
		if r["status"] == "draw":
			draws += 1
		else:
			var wl := _label_of(r, str(r["winner_team"]))
			wins[wl] = int(wins.get(wl, 0)) + 1
	var outcomes := {}
	for l in labels:
		outcomes[l] = _rate(int(wins.get(l, 0)), n)
	out["outcomes"] = {"wins": outcomes, "draws": _rate(draws, n)}
	# distribuciones
	var dist := {}
	for field in ["turns", "end_time", "events"]:
		var vals: Array = finished.map(func(r): return float(r[field]))
		var d := Stats.summarize(vals)
		d["histogram"] = Stats.histogram(vals, bins)
		dist[field] = d
	out["distributions"] = dist
	# dano/curacion por etiqueta y batalla
	var dmg := {}
	var heal := {}
	for l in labels:
		dmg[l] = []
		heal[l] = []
	for r in finished:
		var sides: Dictionary = r.get("sides", {})
		var per: Dictionary = r.get("sides_stats", {})
		for t in sides:
			var l := str(sides[t])
			if per.has(t):
				dmg[l].append(float(per[t]["damage_dealt"]))
				heal[l].append(float(per[t]["healing_done"]))
	out["damage_per_battle"] = {}
	out["healing_per_battle"] = {}
	for l in labels:
		out["damage_per_battle"][l] = Stats.summarize(dmg[l])
		out["healing_per_battle"][l] = Stats.summarize(heal[l])
	out["abilities"] = _abilities(finished, labels)
	out["custom_metrics"] = _custom_metrics(finished)
	# errores y semillas
	out["errors"] = _errors(aborted + setup, max_err)
	var jobs: Array = []
	for r in recs.slice(0, 3):
		jobs.append({"index": r["index"], "repetition": r["repetition"], "seed": str(r["seed"]), "status": r["status"], "log_hash": r.get("log_hash", "")})
	for r in aborted.slice(0, max_err):
		if not jobs.any(func(j): return j["index"] == r["index"]):
			jobs.append({"index": r["index"], "repetition": r["repetition"], "seed": str(r["seed"]), "status": r["status"], "log_hash": r.get("log_hash", "")})
	out["jobs"] = jobs
	return out


static func _abilities(finished: Array, labels: Array) -> Dictionary:
	var out := {}
	for l in labels:
		var names := {}
		for r in finished:
			var sides: Dictionary = r.get("sides", {})
			for t in sides:
				if str(sides[t]) == l:
					for a in (r.get("sides_abilities", {}) as Dictionary).get(t, {}):
						names[a] = true
		var an: Array = names.keys()
		an.sort()
		var rows := {}
		for a in an:
			var used := 0
			var used_wins := 0
			var unused := 0
			var unused_wins := 0
			var uses: Array = []
			var dmg: Array = []
			var heal: Array = []
			for r in finished:
				var sides2: Dictionary = r.get("sides", {})
				for t in sides2:
					if str(sides2[t]) != l:
						continue
					var rec: Dictionary = (r.get("sides_abilities", {}) as Dictionary).get(t, {}).get(a, {"uses": 0, "damage": 0.0, "healing": 0.0})
					var won := 1 if (r["status"] == "win" and str(r["winner_team"]) == str(t)) else 0
					uses.append(float(rec["uses"]))
					dmg.append(float(rec["damage"]))
					heal.append(float(rec["healing"]))
					if int(rec["uses"]) > 0:
						used += 1
						used_wins += won
					else:
						unused += 1
						unused_wins += won
			rows[a] = {"battles": used + unused, "battles_used": used, "usage_rate": _rate(used, used + unused), "mean_uses": Stats.mean(uses),
				"mean_damage": Stats.mean(dmg), "mean_healing": Stats.mean(heal),
				"win_rate_when_used": _rate(used_wins, used), "win_rate_when_unused": _rate(unused_wins, unused)}
		out[l] = rows
	return out


static func _custom_metrics(finished: Array) -> Dictionary:
	var names := {}
	for r in finished:
		for k in (r.get("metrics", {}) as Dictionary):
			names[k] = true
	var keys: Array = names.keys()
	keys.sort()
	var out := {}
	for k in keys:
		var vals: Array = []
		for r in finished:
			vals.append(float(r["metrics"][k]["total"]) if (r.get("metrics", {}) as Dictionary).has(k) else 0.0)
		var s := Stats.summarize(vals)
		s["type"] = "sum"
		s["unit"] = ""
		s["aggregation"] = "total por combate; resumen entre combates"
		out[k] = s
	return out


static func _errors(bad: Array, max_err: int) -> Array:
	var counts := {}
	for r in bad:
		var k := "%s|%s" % [r["status"], str(r.get("error", ""))]
		counts[k] = int(counts.get(k, 0)) + 1
	var keys: Array = counts.keys()
	keys.sort()
	return keys.slice(0, max_err).map(func(k): return {"status": str(k).split("|")[0], "message": str(k).substr(str(k).find("|") + 1), "count": counts[k]})


static func _ranking(recs: Array) -> Array:
	var by := {}
	for r in recs:
		if r["status"] != "win" and r["status"] != "draw":
			continue
		var sides: Dictionary = r.get("sides", {})
		for t in sides:
			var l := str(sides[t])
			if not by.has(l):
				by[l] = {"label": l, "games": 0, "wins": 0, "losses": 0, "draws": 0}
			by[l]["games"] += 1
			if r["status"] == "draw":
				by[l]["draws"] += 1
			elif str(r["winner_team"]) == str(t):
				by[l]["wins"] += 1
			else:
				by[l]["losses"] += 1
	var out: Array = by.values()
	for e in out:
		e["win_rate"] = _rate(int(e["wins"]), int(e["games"]))
		e["score"] = (float(e["wins"]) + 0.5 * float(e["draws"])) / float(e["games"]) if int(e["games"]) > 0 else null
	out.sort_custom(func(x, y): return (float(x["score"]) > float(y["score"])) or (float(x["score"]) == float(y["score"]) and str(x["label"]) < str(y["label"])))
	return out


## Tasa de victorias de cada fila frente a cada columna (todos los escenarios y lados en que se enfrentan).
static func _matrix(recs: Array) -> Dictionary:
	var cells := {}
	var labels := {}
	for r in recs:
		if r["status"] != "win" and r["status"] != "draw":
			continue
		var sides: Dictionary = r.get("sides", {})
		var ts: Array = sides.keys()
		if ts.size() != 2 or str(sides[ts[0]]) == str(sides[ts[1]]):
			continue
		for i in 2:
			var me := str(sides[ts[i]])
			var op := str(sides[ts[1 - i]])
			labels[me] = true
			labels[op] = true
			var key := me + "|" + op
			if not cells.has(key):
				cells[key] = {"row": me, "col": op, "games": 0, "wins": 0, "draws": 0}
			cells[key]["games"] += 1
			if r["status"] == "draw":
				cells[key]["draws"] += 1
			elif str(r["winner_team"]) == str(ts[i]):
				cells[key]["wins"] += 1
	var ls: Array = labels.keys()
	ls.sort()
	var rows: Array = []
	for k in cells.keys():
		var c: Dictionary = cells[k]
		c["win_rate"] = _rate(int(c["wins"]), int(c["games"]))
		rows.append(c)
	rows.sort_custom(func(x, y): return str(x["row"]) + "|" + str(x["col"]) < str(y["row"]) + "|" + str(y["col"]))
	return {"labels": ls, "cells": rows, "note": "favorable si la tasa de la fila supera 0,5; incluye ambos lados y todos los escenarios en que se enfrentan"}


## Comparaciones entre escenarios del mismo grupo (variantes). Resultado = "gana el lado A" (el primer contendiente).
static func _comparisons(by_scen: Dictionary, meta: Dictionary, plan: Dictionary) -> Array:
	var groups := {}
	for k in by_scen:
		var g := str((meta.get(k, {}) as Dictionary).get("group", ""))
		if g != "":
			if not groups.has(g):
				groups[g] = []
			groups[g].append(k)
	var out: Array = []
	var gnames: Array = groups.keys()
	gnames.sort()
	var paired_mode := str(plan.get("seed_mode", "")) == "paired"
	for g in gnames:
		var ks: Array = groups[g]
		ks.sort()
		for i in ks.size():
			for j in range(i + 1, ks.size()):
				out.append(_compare(g, ks[i], ks[j], by_scen, meta, paired_mode))
	return out


static func _a_wins(r: Dictionary) -> bool:
	return r["status"] == "win" and str(r["winner_team"]) == "A"


static func _compare(group: String, ka: String, kb: String, by_scen: Dictionary, meta: Dictionary, paired_mode: bool) -> Dictionary:
	var fa: Array = (by_scen[ka] as Array).filter(func(r): return r["status"] == "win" or r["status"] == "draw")
	var fb: Array = (by_scen[kb] as Array).filter(func(r): return r["status"] == "win" or r["status"] == "draw")
	var ka_wins := fa.filter(func(r): return _a_wins(r)).size()
	var kb_wins := fb.filter(func(r): return _a_wins(r)).size()
	var out := {"group": group, "a": ka, "b": kb, "outcome": "gana el primer contendiente (lado A)",
		"a_label": (meta.get(ka, {}) as Dictionary).get("label", ka), "b_label": (meta.get(kb, {}) as Dictionary).get("label", kb),
		"a_rate": _rate(ka_wins, fa.size()), "b_rate": _rate(kb_wins, fb.size()), "independent": Stats.newcombe_diff(ka_wins, fa.size(), kb_wins, fb.size())}
	if paired_mode:
		var map_b := {}
		for r in fb:
			map_b[int(r["repetition"])] = 1 if _a_wins(r) else 0
		var xa: Array = []
		var xb: Array = []
		for r in fa:
			if map_b.has(int(r["repetition"])):
				xa.append(1 if _a_wins(r) else 0)
				xb.append(map_b[int(r["repetition"])])
		out["paired"] = Stats.paired_binary(xa, xb)
		out["method"] = "emparejada (misma semilla por repeticion)"
	else:
		out["method"] = "independiente (Newcombe)"
	return out
