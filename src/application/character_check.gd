class_name CharacterCheck
extends RefCounted
## Bucle de retroalimentacion para quien CREA un personaje (una IA o una persona): en una biblioteca temporal limpia (no toca la del usuario)
## 1) valida e importa el paquete (errores por archivo y ruta), 2) lo valora con el perfil de costes activo, 3) lo enfrenta a un conjunto de
## oponentes (ejemplos y plantillas) con las mismas semillas y 4) resume resultados y avisos orientativos. Es DETERMINISTA: mismos datos y
## semilla => mismo informe. Los avisos son heuristicas (no verdades de equilibrio) y el perfil de costes por defecto es ILUSTRATIVO.
##
## Los duelos se juegan SIEMPRE con el personaje como equipo A (en caso de empate de iniciativa el orden de alta puede favorecer ligeramente a A).
## `fingerprint` del resultado = SHA-256 de los log_hash de los duelos (reproducible; no depende de rutas temporales).
##
## Uso: `CharacterCheck.run(ruta, {"deps": [rutas], "vs": [ids], "reps": 10, "seed": 1, "budget": "standard", "profile": ""})`.

const DEFAULT_REPS := 10
const MAX_OPPONENTS := 8
const TEMPLATE_LIBS := ["library_abilities", "library_ai"]
const TEMPLATE_CHARS := ["character_minimal", "character_caster", "character_tank_ai", "character_summoner", "character_status_user", "character_with_libraries"]


## Devuelve {"ok", "stage", "errors", "warnings", "diagnostics", "package", "cost", "duels"}. `stage` = donde se detuvo ("import", "deps", "done").
static func run(path: String, opts: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "stage": "import", "errors": [], "warnings": [], "diagnostics": [], "package": {}, "cost": {}, "duels": {}}
	var work := "user://_character_check/%d" % Time.get_ticks_usec()
	var app := AppController.new(work)
	var boot := app.boot()
	if not boot.is_empty():
		out["errors"] = boot
		return _done(out, work)
	if opts.has("profile") or opts.has("budget"):
		var s := {}
		if str(opts.get("profile", "")) != "":
			s["default_profile"] = str(opts["profile"])
		if str(opts.get("budget", "")) != "":
			s["default_budget"] = str(opts["budget"])
		var serr := app.save_settings(s)
		if not serr.is_empty():
			out["errors"] = serr
			return _done(out, work)

	# bibliotecas y oponentes de serie (ejemplos + plantillas)
	var inst := app.install_examples()
	if not (inst["errors"] as Array).is_empty():
		out["errors"] = inst["errors"]
		return _done(out, work)
	for n in TEMPLATE_LIBS + TEMPLATE_CHARS:
		app.importer.commit("res://content/templates/" + n)
	# dependencias propias del creador (rutas), antes del paquete
	out["stage"] = "deps"
	for d in opts.get("deps", []):
		var rd: Dictionary = app.importer.commit(str(d))
		if not bool(rd["ok"]):
			out["errors"].append("dependencia '%s': %s" % [str(d), "; ".join(rd["errors"])])
	if not (out["errors"] as Array).is_empty():
		return _done(out, work)

	# 1. validar e importar
	out["stage"] = "import"
	var pv := app.importer.preview(path)
	# (el aviso "costes no evaluados" del importador usa un perfil tecnico: aqui la valoracion se hace aparte con el perfil activo)
	out["warnings"] = (pv["warnings"] as Array).filter(func(w): return not str(w).contains("costes de creacion no evaluados"))
	if not (pv["errors"] as Array).is_empty() or not bool(pv["ok"]):
		out["errors"] = (pv["errors"] as Array).duplicate() if not (pv["errors"] as Array).is_empty() else ["colision de version"]
		return _done(out, work)
	var cm: Dictionary = app.importer.commit(path)
	if not bool(cm["ok"]):
		out["errors"] = cm["errors"]
		return _done(out, work)
	var id := str(pv["id"])
	var ver := str(pv["version"])
	out["package"] = {"id": id, "version": ver, "type": str(pv["type"]), "hash": str(pv["hash"])}
	if str(pv["type"]) != "character":
		out["stage"] = "done"
		out["ok"] = true
		out["diagnostics"].append("Paquete de biblioteca (%s): validado e importado. Los duelos y la valoracion solo aplican a personajes." % str(pv["type"]))
		return _done(out, work)

	# 2. coste
	out["stage"] = "cost"
	var ev := app.rules.evaluate(id, ver, "", "free", app.budget())
	if (ev.get("technical_errors", []) as Array).size() > 0:
		out["errors"] = ev["technical_errors"]
		return _done(out, work)
	var by := {}
	for it in ev.get("items", []):
		if bool(it["counted"]):
			var c := BalanceCalibrator.category_of(str(it["kind"]))
			by[c] = float(by.get(c, 0.0)) + float(it["amount"])
	out["cost"] = {"profile": str(ev["profile"]["id"]), "illustrative": bool(ev["profile"]["illustrative"]), "creation_cost": ev["creation_cost"],
		"budget_id": str(ev["budget"]["id"]), "budget_points": ev["budget"]["points"], "remaining": ev["remaining"], "within_budget": ev["within_budget"],
		"evaluable": ev["evaluable"], "by_category": by, "unevaluable": (ev["unevaluable"] as Array).map(func(u): return "%s: %s" % [str(u.get("id", "")), str(u.get("reason", ""))])}

	# 3. duelos contra oponentes
	out["stage"] = "duels"
	var reps := int(opts.get("reps", DEFAULT_REPS))
	var seed_v := int(opts.get("seed", 1))
	var opp_ids: Array = []
	if (opts.get("vs", []) as Array).is_empty():
		for e in app.library.entries({"type": "character"}):
			if str(e["id"]) != id and not opp_ids.has(str(e["id"])):
				opp_ids.append(str(e["id"]))
		opp_ids = opp_ids.slice(0, MAX_OPPONENTS)
	else:
		for o in opts["vs"]:
			opp_ids.append(str(o).trim_prefix("pkg:"))
	if opp_ids.is_empty():
		out["errors"].append("no hay oponentes con los que probar")
		return _done(out, work)
	var opponents: Array = opp_ids.map(func(o): return {"label": o, "spec": {"package": o}})
	var prep := app.batch.prepare({"mode": "gauntlet", "reps": reps, "master_seed": seed_v, "subject": {"label": id, "spec": {"package": id, "version": ver}}, "opponents": opponents})
	if not bool(prep["ok"]):
		out["errors"] = prep["errors"]
		return _done(out, work)
	app.batch.start(0)
	var res: BatchResult = app.batch.finish()
	out["duels"] = _summarize(res, id, opp_ids, reps, seed_v)
	var data: Dictionary = app.library.compose(id, ver).get("data", {})
	_diagnose(out, data)
	out["stage"] = "done"
	out["ok"] = true
	return _done(out, work)


static func _done(out: Dictionary, work: String) -> Dictionary:
	ContentLibrary._remove_tree(work)
	return out


static func _summarize(res: BatchResult, id: String, opp_ids: Array, reps: int, seed_v: int) -> Dictionary:
	var per := {}
	for o in opp_ids:
		per[o] = {"id": o, "games": 0, "wins": 0, "losses": 0, "draws": 0, "turns": 0, "win_rate": 0.0, "avg_turns": 0.0}
	var abil := {}
	var aborted := 0
	var games := 0
	var hc := HashingContext.new()
	hc.start(HashingContext.HASH_SHA256)
	for rec in res.records:
		if not (rec is Dictionary):
			continue
		var st := str(rec.get("status", ""))
		hc.update(("%s\n" % str(rec.get("log_hash", ""))).to_utf8_buffer())
		if not ["win", "draw"].has(st):
			aborted += 1
			continue
		var opp := str((rec["sides"] as Dictionary).get("B", ""))
		var p: Dictionary = per[opp]
		p["games"] += 1
		p["turns"] += int(rec["turns"])
		games += 1
		if st == "draw":
			p["draws"] += 1
		elif str(rec["winner_team"]) == "A":
			p["wins"] += 1
		else:
			p["losses"] += 1
		for a in (rec.get("sides_abilities", {}) as Dictionary).get("A", {}):
			var ab: Dictionary = rec["sides_abilities"]["A"][a]
			if not abil.has(a):
				abil[a] = {"id": a, "uses": 0, "damage": 0.0, "healing": 0.0}
			abil[a]["uses"] += int(ab["uses"])
			abil[a]["damage"] += float(ab["damage"])
			abil[a]["healing"] += float(ab["healing"])
	var opps: Array = []
	var wins := 0
	var draws := 0
	for o in opp_ids:
		var p: Dictionary = per[o]
		if int(p["games"]) > 0:
			p["win_rate"] = float(p["wins"]) / float(p["games"])
			p["avg_turns"] = float(p["turns"]) / float(p["games"])
		wins += int(p["wins"])
		draws += int(p["draws"])
		p.erase("turns")
		opps.append(p)
	var ab_list: Array = abil.values()
	ab_list.sort_custom(func(x, y): return str(x["id"]) < str(y["id"]))
	return {"reps": reps, "seed": seed_v, "opponents": opps, "games": games, "aborted": aborted,
		"win_rate": float(wins) / float(games) if games > 0 else 0.0, "draw_rate": float(draws) / float(games) if games > 0 else 0.0,
		"abilities": ab_list, "fingerprint": hc.finish().hex_encode()}


## Avisos orientativos (heuristicas, no verdades de equilibrio).
static func _diagnose(out: Dictionary, data: Dictionary) -> void:
	var d: Array = out["diagnostics"]
	var du: Dictionary = out["duels"]
	var cost: Dictionary = out["cost"]
	if int(du["aborted"]) > 0:
		d.append("ERROR TECNICO: %d duelos abortados (formula/script con error, limite alcanzado...). Reproduzca uno con tools/run_duel.gd --log." % int(du["aborted"]))
	if int(du["games"]) == 0:
		d.append("No se completo ningun duelo.")
		return
	var wr := float(du["win_rate"])
	if wr >= 0.8:
		d.append("Gana el %.0f%% de los duelos: probablemente DEMASIADO fuerte para su coste (%s puntos)." % [wr * 100.0, ReportDocument.num(cost["creation_cost"])])
	elif wr <= 0.2:
		d.append("Gana solo el %.0f%% de los duelos: probablemente DEMASIADO debil (o su IA no usa bien sus habilidades)." % [wr * 100.0])
	if float(du["draw_rate"]) >= 0.2:
		d.append("El %.0f%% de los duelos acaba en empate/limite: quizá le falta dano, o cura/protege mas de lo que daña." % [float(du["draw_rate"]) * 100.0])
	var turns := 0.0
	for o in du["opponents"]:
		turns += float(o["avg_turns"])
	turns /= maxf(float(du["opponents"].size()), 1.0)
	if turns > 0.0 and turns < 3.0:
		d.append("Duelos muy cortos (%.1f turnos de media): un solo golpe decide; revise multiplicadores de daño y vida." % turns)
	elif turns > 40.0:
		d.append("Duelos muy largos (%.0f turnos de media): poco dano o demasiada curacion/defensa." % turns)
	var used := {}
	for a in du["abilities"]:
		if int(a["uses"]) > 0:
			used[str(a["id"])] = true
	for a in data.get("abilities", []):
		var aid := str(a.get("id", ""))
		if aid == "" or aid == "(otros)" or used.has(aid) or a.has("trigger") or a.has("passive"):
			continue
		d.append("La habilidad '%s' NO se uso en ningun duelo: revise la IA (reglas/pesos/condiciones), su coste en recursos o sus restricciones (cooldown, requires)." % aid)
	if not bool(cost.get("within_budget", true)):
		d.append("Cuesta %s puntos y el presupuesto '%s' es %s: en modo reglamentado se rechazaria." % [ReportDocument.num(cost["creation_cost"]), cost["budget_id"], ReportDocument.num(cost["budget_points"])])
	if not (cost.get("unevaluable", []) as Array).is_empty():
		d.append("Hay componentes no evaluables (no suman coste): %s" % "; ".join(cost["unevaluable"]))
	if bool(cost.get("illustrative", true)):
		d.append("Los costes usan un perfil ILUSTRATIVO (cifras de prueba, no definitivas).")


static func to_markdown(r: Dictionary) -> String:
	var s := "# Comprobacion de personaje\n\n"
	if not bool(r["ok"]):
		s += "**RECHAZADO en la etapa `%s`:**\n" % r["stage"]
		for e in r["errors"]:
			s += "- %s\n" % str(e)
		return s
	var p: Dictionary = r["package"]
	s += "**OK** `%s@%s` (%s) hash `%s`\n\n" % [p["id"], p["version"], p["type"], str(p["hash"]).substr(0, 12)]
	for w in r["warnings"]:
		s += "- aviso: %s\n" % str(w)
	if not (r["cost"] as Dictionary).is_empty():
		var c: Dictionary = r["cost"]
		s += "\n## Coste de creacion (perfil `%s`%s)\n- Coste: **%s** de %s (`%s`) · restante %s · dentro del presupuesto: %s\n" % [c["profile"], " ILUSTRATIVO" if c["illustrative"] else "",
			ReportDocument.num(c["creation_cost"]), ReportDocument.num(c["budget_points"]), c["budget_id"], ReportDocument.num(c["remaining"]), "si" if c["within_budget"] else "NO"]
		for k in c["by_category"]:
			s += "- %s: %s\n" % [k, ReportDocument.num(c["by_category"][k])]
	if not (r["duels"] as Dictionary).is_empty():
		var du: Dictionary = r["duels"]
		s += "\n## Duelos (%d por rival, jugando como equipo A, semilla %d)\n\n| Oponente | Duelos | Victorias | Derrotas | Empates | %% victorias | Turnos |\n|---|---:|---:|---:|---:|---:|---:|\n" % [du["reps"], du["seed"]]
		for o in du["opponents"]:
			s += "| %s | %d | %d | %d | %d | %.0f%% | %.1f |\n" % [o["id"], o["games"], o["wins"], o["losses"], o["draws"], float(o["win_rate"]) * 100.0, o["avg_turns"]]
		s += "\nTotal: %d duelos, victorias %.0f%%, empates %.0f%%.\n\n| Habilidad | Usos | Dano | Curacion |\n|---|---:|---:|---:|\n" % [du["games"], float(du["win_rate"]) * 100.0, float(du["draw_rate"]) * 100.0]
		for a in du["abilities"]:
			s += "| %s | %d | %s | %s |\n" % [a["id"], a["uses"], ReportDocument.num(a["damage"]), ReportDocument.num(a["healing"])]
	s += "\n## Diagnostico (orientativo)\n"
	for x in r["diagnostics"]:
		s += "- %s\n" % str(x)
	if (r["diagnostics"] as Array).is_empty():
		s += "- Sin avisos.\n"
	return s
