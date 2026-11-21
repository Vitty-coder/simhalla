class_name BalanceCalibrator
extends RefCounted
## Calibrador EMPIRICO de costes (PROJECT.md §9/§21; D-118). NO inventa cifras: parte de un perfil existente, valora a cada contendiente,
## los enfrenta en un torneo todos-contra-todos y estima cuanto PODER da cada punto de coste en cada categoria, para proponer un perfil
## con multiplicadores por categoria. El resultado es una PROPUESTA etiquetada ILUSTRATIVA que una persona revisa; nunca se aplica sola.
##
## Metodo (determinista dada la semilla):
##  1. coste_i por categoria (stats, abilities, statuses, resources, other) = suma de items CONTADOS del informe de valoracion.
##  2. poder_i = log-odds suavizado (Laplace) de la puntuacion del torneo (victoria=1, empate=0.5).
##  3. regresion ridge de poder_i sobre los costes por categoria, con contraccion hacia la pendiente global del coste total:
##     beta_k = poder ganado por punto en la categoria k. multiplicador_k = beta_k / beta_global, acotado [0.5, 2], renormalizado para
##     que el coste medio ponderado se conserve (los presupuestos siguen significando lo mismo) y acotado de nuevo.
##  4. propuesta = perfil con cada formula de la categoria envuelta en `(formula) * m`; se re-valora para informar la mejora.
## Limites: pocos contendientes = poca fiabilidad (aviso bajo MIN_RECOMMENDED); mide correlacion en ESTE conjunto, no equilibrio universal.

const CATEGORIES := ["stats", "abilities", "statuses", "resources", "other"]
const SCALABLE := ["stats", "abilities", "statuses", "resources"]
const MIN_RECOMMENDED := 6
const MIN_ENTITIES := 4
const MULT_MIN := 0.5
const MULT_MAX := 2.0


static func category_of(kind: String) -> String:
	if kind == "stat" or kind == "stat_credit" or kind.begins_with("modifier"):
		return "stats"
	match kind:
		"ability":
			return "abilities"
		"status_def":
			return "statuses"
		"resource":
			return "resources"
	return "other"


## Trabajo de calibracion ejecutable por tramos (la interfaz no se congela): `step()` hasta `is_done()`, luego `finish()`.
class Job extends RefCounted:
	var contestants: Array = []
	var profile: BalanceProfile
	var ruleset: Ruleset
	var registry: OperationRegistry
	var opts: Dictionary = {}
	var costs: Array = []
	var out: Dictionary = {}
	var runner: BatchRunner

	## Ejecuta trabajos del torneo durante ~max_ms. Devuelve el progreso {total, done, ...}.
	func step(max_ms: int = 8) -> Dictionary:
		return runner.run_slice(1000000, max_ms)

	func is_done() -> bool:
		return runner.is_finished()

	func cancel() -> void:
		runner.cancel()

	func progress() -> Dictionary:
		return runner.progress()

	## Analiza el torneo terminado. Un torneo cancelado devuelve {ok: false, cancelled: true}.
	func finish() -> Dictionary:
		var res: BatchResult = runner.wait()
		if res.status == "cancelled":
			out["ok"] = false
			out["cancelled"] = true
			out["errors"] = ["calibracion cancelada"]
			return out
		return BalanceCalibrator._analyze(self, res)


## Version sincrona (herramientas y pruebas): begin + ejecutar todo + finish.
## contestants: [{label, spec, data}]. opts: {reps=10, master_seed=1, workers=0, base={}, mode="free"}.
## Devuelve {"ok", "errors", "warnings", "entities", "categories", "summary", "suggested_profile"|null, "plan_fingerprint", "result_fingerprint"}.
static func calibrate(contestants: Array, profile: BalanceProfile, ruleset: Ruleset, registry: OperationRegistry, opts: Dictionary = {}) -> Dictionary:
	var b := begin(contestants, profile, ruleset, registry, opts)
	if not bool(b["ok"]):
		return b
	return (b["job"] as Job).finish()


## Valida, valora a los contendientes y prepara el torneo SIN ejecutarlo. {"ok": true, "job": Job} o {"ok": false, "errors", ...}.
static func begin(contestants: Array, profile: BalanceProfile, ruleset: Ruleset, registry: OperationRegistry, opts: Dictionary = {}) -> Dictionary:
	var out := {"ok": false, "errors": [], "warnings": [], "entities": [], "categories": [], "summary": {}, "suggested_profile": null}
	if not profile.has_costs():
		out["errors"].append("el perfil '%s' no define costes: no hay nada que calibrar" % profile.id)
		return out
	if contestants.size() < MIN_ENTITIES:
		out["errors"].append("hacen falta al menos %d contendientes (hay %d)" % [MIN_ENTITIES, contestants.size()])
		return out
	var labels := {}
	for c in contestants:
		if labels.has(str(c["label"])):
			out["errors"].append("etiqueta repetida '%s'" % str(c["label"]))
		labels[str(c["label"])] = true
	if not (out["errors"] as Array).is_empty():
		return out
	if contestants.size() < MIN_RECOMMENDED:
		out["warnings"].append("solo %d contendientes: la calibracion es poco fiable (recomendado >= %d)" % [contestants.size(), MIN_RECOMMENDED])
	var reps := int(opts.get("reps", 10))
	if reps < 10:
		out["warnings"].append("pocas repeticiones (%d): el poder medido es ruidoso" % reps)
	var costs: Array = []
	for c in contestants:
		var v := _value(c, profile, ruleset, registry, str(opts.get("mode", "free")))
		if not (v["errors"] as Array).is_empty():
			out["errors"].append("%s: %s" % [c["label"], "; ".join(v["errors"])])
		costs.append(v)
	if not (out["errors"] as Array).is_empty():
		return out
	for i in contestants.size():
		for u in costs[i]["unevaluable"]:
			out["warnings"].append("%s: componente no evaluable '%s' (no suma al coste)" % [contestants[i]["label"], u])
	var specs: Array = contestants.map(func(c): return {"label": c["label"], "spec": c["spec"]})
	var plan_r := BatchPlan.from_dict(BatchModes.tournament(specs, reps, int(opts.get("master_seed", 1)), opts.get("base", {}), true))
	if not (plan_r["errors"] as Array).is_empty():
		out["errors"].append_array(plan_r["errors"])
		return out
	var job := Job.new()
	job.contestants = contestants
	job.profile = profile
	job.ruleset = ruleset
	job.registry = registry
	job.opts = opts
	job.costs = costs
	job.out = out
	job.runner = BatchRunner.new(plan_r["plan"], {"workers": int(opts.get("workers", 0))})
	return {"ok": true, "job": job}


## Analisis tras el torneo (puntuacion, poder, regresion, propuesta).
static func _analyze(job: Job, res: BatchResult) -> Dictionary:
	var out: Dictionary = job.out
	var contestants: Array = job.contestants
	var costs: Array = job.costs
	var profile: BalanceProfile = job.profile
	var ruleset: Ruleset = job.ruleset
	var registry: OperationRegistry = job.registry
	var opts: Dictionary = job.opts
	var reps := int(opts.get("reps", 10))
	out["plan_fingerprint"] = res.plan_fingerprint
	out["result_fingerprint"] = res.fingerprint
	var score := {}
	var games := {}
	for c in contestants:
		score[str(c["label"])] = 0.0
		games[str(c["label"])] = 0
	var bad := 0
	for rec in res.records:
		if not (rec is Dictionary) or not ["win", "draw"].has(str(rec.get("status", ""))):
			bad += 1
			continue
		var sides: Dictionary = rec["sides"]
		var la := str(sides.get("A", ""))
		var lb := str(sides.get("B", ""))
		games[la] += 1
		games[lb] += 1
		if str(rec["status"]) == "draw":
			score[la] += 0.5
			score[lb] += 0.5
		elif str(rec["winner_team"]) == "A":
			score[la] += 1.0
		else:
			score[lb] += 1.0
	if bad > 0:
		out["warnings"].append("%d duelos abortados o no ejecutados quedaron fuera de la puntuacion" % bad)

	# 3. poder y regresion
	var n := contestants.size()
	var rating: Array = []
	var cat_costs: Array = []
	var total: Array = []
	for i in n:
		var lab := str(contestants[i]["label"])
		var g := int(games[lab])
		if g == 0:
			out["errors"].append("%s: sin duelos validos" % lab)
			return out
		var s := (float(score[lab]) + 0.5) / (float(g) + 1.0)
		rating.append(log(s / (1.0 - s)))
		cat_costs.append(costs[i]["by_cat"])
		total.append(costs[i]["total"])
	var fit := _fit(rating, cat_costs, total)
	for w in fit["warnings"]:
		out["warnings"].append(w)
	var mult: Dictionary = fit["multipliers"]

	# 4. propuesta y re-valoracion
	var suggested: Variant = null
	var after_costs: Array = []
	if bool(fit["usable"]):
		suggested = _scaled_profile(profile, mult, contestants.size(), reps, int(opts.get("master_seed", 1)))
		var sp := BalanceProfile.from_dict(suggested)
		if not sp.is_valid():
			out["errors"].append("el perfil propuesto no es valido: %s" % "; ".join(sp.errors))
			return out
		for c in contestants:
			after_costs.append(_value(c, sp, ruleset, registry, str(opts.get("mode", "free")))["total"])
	var ents: Array = []
	for i in n:
		var lab := str(contestants[i]["label"])
		var e := {"label": lab, "cost": total[i], "by_category": cat_costs[i], "score": score[lab] / float(games[lab]), "games": games[lab], "rating": rating[i],
			"residual": fit["residuals"][i], "verdict": fit["verdicts"][i]}
		if not after_costs.is_empty():
			e["cost_after"] = after_costs[i]
		ents.append(e)
	var summary := {"contestants": n, "repetitions": reps, "master_seed": int(opts.get("master_seed", 1)), "duels": res.total_jobs,
		"spearman_before": spearman(total, rating), "slope": fit["slope"], "usable": fit["usable"]}
	if not after_costs.is_empty():
		summary["spearman_after"] = spearman(after_costs, rating)
	var cats: Array = []
	for k in CATEGORIES:
		cats.append({"id": k, "beta": fit["betas"].get(k, 0.0), "multiplier": mult.get(k, 1.0), "identifiable": fit["identifiable"].get(k, false)})
	out["ok"] = true
	out["entities"] = ents
	out["categories"] = cats
	out["summary"] = summary
	out["suggested_profile"] = suggested
	return out


## {"total", "by_cat", "errors", "unevaluable"} del informe de valoracion de un contendiente.
static func _value(c: Dictionary, profile: BalanceProfile, ruleset: Ruleset, registry: OperationRegistry, mode: String) -> Dictionary:
	var d: Dictionary = (c["data"] as Dictionary).duplicate(true)
	if not d.has("id"):
		d["id"] = str(c["label"])
	if not d.has("team"):
		d["team"] = "x"
	var rep := BalanceEvaluator.evaluate(d, profile, ruleset, registry, {"mode": mode})
	var by := {}
	for k in CATEGORIES:
		by[k] = 0.0
	for it in rep.items:
		if bool(it["counted"]):
			by[category_of(str(it["kind"]))] += float(it["amount"])
	var errs: Array = (rep.technical_errors as Array).duplicate()
	return {"total": rep.creation_cost, "by_cat": by, "errors": errs, "unevaluable": rep.unevaluable.map(func(u): return str(u.get("id", u)) if u is Dictionary else str(u))}


## Regresion ridge descrita arriba. Devuelve {usable, slope, betas, multipliers, identifiable, residuals, verdicts, warnings}.
static func _fit(y: Array, cat_costs: Array, total: Array) -> Dictionary:
	var n := y.size()
	var out := {"usable": false, "slope": 0.0, "betas": {}, "multipliers": {}, "identifiable": {}, "residuals": [], "verdicts": [], "warnings": []}
	var ym := _mean(y)
	var tm := _mean(total)
	var stt := 0.0
	var sty := 0.0
	for i in n:
		stt += (float(total[i]) - tm) * (float(total[i]) - tm)
		sty += (float(total[i]) - tm) * (float(y[i]) - ym)
	var resid: Array = []
	if stt < 1e-9:
		out["warnings"].append("todos los contendientes cuestan lo mismo: no se puede calibrar")
		for i in n:
			resid.append(float(y[i]) - ym)
	else:
		out["slope"] = sty / stt
		for i in n:
			resid.append((float(y[i]) - ym) - out["slope"] * (float(total[i]) - tm))
	var sd := sqrt(_var(resid))
	out["residuals"] = resid
	for i in n:
		out["verdicts"].append("subvalorado" if sd > 1e-9 and resid[i] > sd else ("sobrevalorado" if sd > 1e-9 and resid[i] < -sd else "acorde"))
	if stt < 1e-9:
		return out
	var beta0: float = out["slope"]
	if beta0 <= 0.0:
		out["warnings"].append("el coste total NO predice el poder en este conjunto (pendiente <= 0): no se propone perfil")
		return out
	# categorias identificables (varianza > 0)
	var ks: Array = []
	for k in SCALABLE:
		var col: Array = cat_costs.map(func(c): return float(c[k]))
		var identifiable := _var(col) > 1e-9
		out["identifiable"][k] = identifiable
		if identifiable:
			ks.append(k)
	if ks.is_empty():
		out["warnings"].append("ninguna categoria varia entre contendientes: no se puede calibrar")
		return out
	var K := ks.size()
	var X: Array = []
	for i in n:
		var row: Array = []
		for k in ks:
			var col: Array = cat_costs.map(func(c): return float(c[k]))
			row.append(float(cat_costs[i][k]) - _mean(col))
		X.append(row)
	var A: Array = []
	var b: Array = []
	var trace := 0.0
	for p in K:
		var row2: Array = []
		var bp := 0.0
		for q in K:
			var s := 0.0
			for i in n:
				s += float(X[i][p]) * float(X[i][q])
			row2.append(s)
			if p == q:
				trace += s
		for i in n:
			bp += float(X[i][p]) * (float(y[i]) - ym)
		A.append(row2)
		b.append(bp)
	var lambda := 0.5 * trace / float(K)
	for p in K:
		A[p][p] += lambda
		b[p] += lambda * beta0
	var beta := _solve(A, b)
	if beta.is_empty():
		out["warnings"].append("sistema singular: no se propone perfil")
		return out
	var raw := {}
	for p in K:
		out["betas"][ks[p]] = beta[p]
		raw[ks[p]] = clampf(float(beta[p]) / beta0, MULT_MIN, MULT_MAX)
	# renormalizar: el coste medio ponderado por categoria no cambia
	var weight := 0.0
	var gross := 0.0
	for k in ks:
		var c := 0.0
		for e in cat_costs:
			c += maxf(float(e[k]), 0.0)
		weight += c * float(raw[k])
		gross += c
	var norm := (gross / weight) if weight > 1e-9 else 1.0
	for k in SCALABLE:
		# tras renormalizar se vuelve a acotar (el coste medio puede desviarse algo, pero ningun multiplicador sale de [MULT_MIN, MULT_MAX])
		out["multipliers"][k] = snappedf(clampf(float(raw[k]) * norm, MULT_MIN, MULT_MAX), 0.001) if raw.has(k) else 1.0
	out["usable"] = true
	return out


## Perfil propuesto: cada formula de una categoria con m != 1 se envuelve en `(formula) * m`. Siempre ILUSTRATIVO y con procedencia en la descripcion.
static func _scaled_profile(profile: BalanceProfile, mult: Dictionary, n: int, reps: int, seed_value: int) -> Dictionary:
	var d := profile.to_dict()
	var c: Dictionary = d["costs"]
	var wrap := func(rule: Dictionary, m: float) -> void:
		if rule.has("formula") and absf(m - 1.0) > 1e-9:
			rule["formula"] = "(%s) * %s" % [str(rule["formula"]), _num(m)]
	var m_stats: float = mult.get("stats", 1.0)
	if c.has("stats"):
		var st: Dictionary = c["stats"]
		for key in ["default", "custom"]:
			if st.get(key, null) is Dictionary:
				wrap.call(st[key], m_stats)
		for group in ["rules", "patterns"]:
			if st.get(group, null) is Dictionary:
				for r in st[group]:
					wrap.call(st[group][r], m_stats)
	for pair in [["abilities", "ability"], ["statuses", "status_def"], ["resources", "resource"]]:
		if c.has(pair[1]) and c[pair[1]] is Dictionary:
			wrap.call(c[pair[1]], float(mult.get(pair[0], 1.0)))
	d["id"] = "%s_cal" % profile.id if not profile.id.ends_with("_cal") else profile.id
	d["version"] = _bump(profile.version)
	d["illustrative"] = true
	d["description"] = "PROPUESTA calibrada empiricamente a partir de %s@%s con %d contendientes, %d repeticiones por emparejamiento y semilla maestra %d. Multiplicadores por categoria: %s. ILUSTRATIVA: revisar antes de usar como referencia." % [
		profile.id, profile.version, n, reps, seed_value, ", ".join(SCALABLE.map(func(k): return "%s=%s" % [k, _num(float(mult.get(k, 1.0)))]))]
	return d


static func _bump(version: String) -> String:
	var p := SemVer.parse(version)
	if p.size() < 3:
		return "0.1.1"
	return "%d.%d.%d" % [int(p[0]), int(p[1]), int(p[2]) + 1]


static func _num(v: float) -> String:
	var s := "%.3f" % v
	while s.ends_with("0") and s.contains("."):
		s = s.left(s.length() - 1)
	return s.trim_suffix(".")


static func _mean(a: Array) -> float:
	if a.is_empty():
		return 0.0
	var s := 0.0
	for x in a:
		s += float(x)
	return s / float(a.size())


static func _var(a: Array) -> float:
	var m := _mean(a)
	var s := 0.0
	for x in a:
		s += (float(x) - m) * (float(x) - m)
	return s / float(maxi(a.size(), 1))


## Resuelve A x = b (eliminacion gaussiana con pivote parcial). [] si es singular.
static func _solve(A: Array, b: Array) -> Array:
	var n := b.size()
	var M: Array = []
	for i in n:
		var row: Array = (A[i] as Array).duplicate()
		row.append(b[i])
		M.append(row)
	for col in n:
		var piv := col
		for r in range(col + 1, n):
			if absf(float(M[r][col])) > absf(float(M[piv][col])):
				piv = r
		if absf(float(M[piv][col])) < 1e-12:
			return []
		var tmp: Array = M[col]
		M[col] = M[piv]
		M[piv] = tmp
		for r in range(col + 1, n):
			var f := float(M[r][col]) / float(M[col][col])
			for c in range(col, n + 1):
				M[r][c] = float(M[r][c]) - f * float(M[col][c])
	var x: Array = []
	x.resize(n)
	for i in range(n - 1, -1, -1):
		var s := float(M[i][n])
		for j in range(i + 1, n):
			s -= float(M[i][j]) * float(x[j])
		x[i] = s / float(M[i][i])
	return x


static func _ranks(a: Array) -> Array:
	var idx: Array = range(a.size())
	idx.sort_custom(func(i, j): return float(a[i]) < float(a[j]))
	var r: Array = []
	r.resize(a.size())
	var i := 0
	while i < idx.size():
		var j := i
		while j + 1 < idx.size() and absf(float(a[idx[j + 1]]) - float(a[idx[i]])) < 1e-12:
			j += 1
		var avg := (float(i) + float(j)) / 2.0 + 1.0
		for k in range(i, j + 1):
			r[idx[k]] = avg
		i = j + 1
	return r


## Correlacion de Spearman (Pearson sobre rangos con empates promediados); 0.0 si no hay varianza.
static func spearman(a: Array, b: Array) -> float:
	if a.size() != b.size() or a.size() < 2:
		return 0.0
	var ra := _ranks(a)
	var rb := _ranks(b)
	var ma := _mean(ra)
	var mb := _mean(rb)
	var sab := 0.0
	var saa := 0.0
	var sbb := 0.0
	for i in ra.size():
		sab += (float(ra[i]) - ma) * (float(rb[i]) - mb)
		saa += (float(ra[i]) - ma) * (float(ra[i]) - ma)
		sbb += (float(rb[i]) - mb) * (float(rb[i]) - mb)
	if saa < 1e-12 or sbb < 1e-12:
		return 0.0
	return sab / sqrt(saa * sbb)


static func to_markdown(r: Dictionary) -> String:
	var s := "# Calibracion empirica de costes\n\n> PROPUESTA ILUSTRATIVA: mide correlacion coste/poder en este conjunto de contendientes; no es un equilibrio definitivo ni se aplica sola.\n\n"
	if not bool(r.get("ok", false)):
		return s + "**Error:** %s\n" % "; ".join(r.get("errors", []))
	var sm: Dictionary = r["summary"]
	s += "- Contendientes: %d · repeticiones: %d · duelos: %d · semilla: %d\n- Spearman coste-poder: **%.3f**%s\n" % [sm["contestants"], sm["repetitions"], sm["duels"], sm["master_seed"], sm["spearman_before"],
		(" → %.3f con la propuesta" % sm["spearman_after"]) if sm.has("spearman_after") else ""]
	for w in r["warnings"]:
		s += "- AVISO: %s\n" % str(w)
	s += "\n| Contendiente | Coste | Puntuacion | Poder (logit) | Veredicto |\n|---|---:|---:|---:|---|\n"
	for e in r["entities"]:
		s += "| %s | %.1f | %.3f | %.2f | %s |\n" % [e["label"], e["cost"], e["score"], e["rating"], e["verdict"]]
	s += "\n| Categoria | Poder/punto (beta) | Multiplicador | Identificable |\n|---|---:|---:|---|\n"
	for c in r["categories"]:
		s += "| %s | %.4f | %s | %s |\n" % [c["id"], c["beta"], _num(float(c["multiplier"])), "si" if bool(c["identifiable"]) else "no"]
	if r["suggested_profile"] == null:
		s += "\nSin perfil propuesto.\n"
	else:
		s += "\nPerfil propuesto: `%s@%s` (ILUSTRATIVO).\n" % [r["suggested_profile"]["id"], r["suggested_profile"]["version"]]
	return s
