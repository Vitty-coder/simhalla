class_name ScoredAI
extends AIController
## IA de puntuaciones dinamicas: puntua TODAS las parejas (habilidad legal, objetivo)
## y elige la de mayor puntuacion. Desempate determinista: primera en el orden de
## la vista (habilidades por orden de alta, objetivos por orden de aparicion).
##
## {"type":"scored",
##  "weights":{"damage":1.0,"lethal":50,"heal":0.8,"need":2,"low_target":1,"status":0.5,"cost":-0.3,"hit":0.2},
##  "bias":{"fireball":1.5}, "tag_bias":{"burst":2},
##  "modifiers":[{"when":{"self.hp_ratio":{"lt":0.3}},"weights":{"heal":4},"bias":{"mend":3}}],
##  "exclude":["suicide"], "wait_below": 0.5}
##
## Caracteristicas (todas en 0..1 salvo indicacion; calculadas con AIPredictor, solo informacion visible):
##   damage       dano esperado ponderado (impacto y critico) / vida visible del objetivo
##   lethal       1 si el dano esperado conocido basta para matar
##   lethal_potential  1 si el dano maximo posible bastaria
##   heal         curacion efectiva / vida maxima del objetivo
##   need         (1 - hp_ratio del objetivo) si la habilidad cura
##   low_target   (1 - hp_ratio del objetivo) si la habilidad hace dano a un rival
##   status       1 si aplica algun estado que el objetivo no tiene (o no es visible)
##   hit          probabilidad estimada de impactar (habilidades de dano)
##   tempo        1 - fraccion del intervalo de turno que le falta al rival (alto = actua pronto); 0 si no se ha observado
##   reaction_risk  1 si la habilidad daña a un rival del que se han visto reacciones (usar peso negativo)
##   cost         coste relativo a los recursos actuales (usar peso negativo para conservar)
## Danar a aliados/uno mismo invierte el signo de `damage`/`lethal`; curar a rivales invierte `heal`.
## `modifiers`: si su `when` (ambito state) se cumple, suman sus pesos/bias.
## `wait_below`: si la mejor puntuacion es menor, espera (reservar recursos/accion).

const FEATURES := ["damage", "lethal", "lethal_potential", "heal", "need", "low_target", "status", "hit", "cost", "tempo", "reaction_risk"]
const TOP_N := 5

var weights: Dictionary = {}
var bias: Dictionary = {}
var tag_bias: Dictionary = {}
var modifiers: Array = []
var exclude: Array = []
var wait_below: Variant = null


static func validate(cfg: Dictionary) -> Array:
	var errs: Array = []
	for k in cfg:
		if not ["type", "weights", "bias", "tag_bias", "modifiers", "exclude", "wait_below", "reactions"].has(str(k)):
			errs.append("ia scored: propiedad desconocida '%s'" % str(k))
	errs.append_array(_num_map(cfg.get("weights", {}), "ia scored.weights", FEATURES))
	errs.append_array(_num_map(cfg.get("bias", {}), "ia scored.bias", []))
	errs.append_array(_num_map(cfg.get("tag_bias", {}), "ia scored.tag_bias", []))
	if cfg.has("exclude") and not (cfg["exclude"] is Array):
		errs.append("ia scored.exclude: debe ser una lista")
	if cfg.has("wait_below") and not (cfg["wait_below"] is float or cfg["wait_below"] is int):
		errs.append("ia scored.wait_below: debe ser numerico")
	var ms: Variant = cfg.get("modifiers", [])
	if not (ms is Array):
		errs.append("ia scored.modifiers: debe ser una lista")
	else:
		if (ms as Array).size() > 32:
			errs.append("ia scored.modifiers: maximo 32")
		for i in (ms as Array).size():
			var m: Variant = ms[i]
			var w := "ia scored.modifiers[%d]" % i
			if not (m is Dictionary):
				errs.append("%s: debe ser un objeto" % w)
				continue
			for k in m:
				if not ["when", "weights", "bias"].has(str(k)):
					errs.append("%s: propiedad desconocida '%s'" % [w, str(k)])
			errs.append_array(AIConditions.validate(m.get("when", {}), w, "state"))
			errs.append_array(_num_map(m.get("weights", {}), w + ".weights", FEATURES))
			errs.append_array(_num_map(m.get("bias", {}), w + ".bias", []))
	return errs


static func _num_map(m: Variant, where: String, allowed: Array) -> Array:
	var errs: Array = []
	if not (m is Dictionary):
		return ["%s: debe ser un objeto" % where]
	for k in m:
		if not allowed.is_empty() and not allowed.has(str(k)):
			errs.append("%s: caracteristica desconocida '%s' (use: %s)" % [where, str(k), ", ".join(allowed)])
		if not (m[k] is float or m[k] is int):
			errs.append("%s.%s: debe ser numerico" % [where, str(k)])
	return errs


static func from_dict(cfg: Dictionary) -> ScoredAI:
	var ai := ScoredAI.new()
	ai.weights = (cfg.get("weights", {}) as Dictionary).duplicate()
	ai.bias = (cfg.get("bias", {}) as Dictionary).duplicate()
	ai.tag_bias = (cfg.get("tag_bias", {}) as Dictionary).duplicate()
	ai.modifiers = (cfg.get("modifiers", []) as Array).duplicate(true)
	ai.exclude = (cfg.get("exclude", []) as Array).duplicate()
	ai.wait_below = cfg.get("wait_below", null)
	return ai


func ai_id() -> String:
	return "scored"


func wants_memory() -> bool:
	return true


func referenced_abilities() -> Array:
	var out: Array = super.referenced_abilities()
	out.append_array(bias.keys())
	out.append_array(exclude)
	for m in modifiers:
		out.append_array((m.get("bias", {}) as Dictionary).keys())
	return out


func decide(view: Dictionary) -> AIDecision:
	var w := weights.duplicate()
	var b := bias.duplicate()
	var active: Array = []
	var sctx := {"view": view, "target": null, "predict": null, "event": null}
	for i in modifiers.size():
		var m: Dictionary = modifiers[i]
		if AIConditions.holds(m.get("when", {}), sctx):
			active.append(i)
			for k in m.get("weights", {}):
				w[k] = float(w.get(k, 0.0)) + float(m["weights"][k])
			for k in m.get("bias", {}):
				b[k] = float(b.get(k, 0.0)) + float(m["bias"][k])
	var abil: Dictionary = {}
	for a in view["self"]["abilities"]:
		abil[a["id"]] = a
	var cands: Array = []
	var excluded: Array = []
	for la in view["legal_actions"]:
		var aid: String = la["ability_id"]
		if exclude.has(aid):
			excluded.append(aid)
			continue
		for tid in la["targets"]:
			var tdict: Variant = PriorityListAI._entity(view, str(tid))
			if tdict == null or not bool(tdict.get("alive", true)):
				continue
			var feats := _features(view, aid, str(tid), tdict, abil[aid])
			var score := float(b.get(aid, 0.0))
			for t in abil[aid]["tags"]:
				score += float(tag_bias.get(str(t), 0.0))
			for f in feats:
				score += float(w.get(f, 0.0)) * float(feats[f])
			cands.append({"ability": aid, "target": str(tid), "score": score, "features": feats})
	var details := {"candidates_total": cands.size(), "modifiers": active, "excluded": excluded}
	if cands.is_empty():
		return AIDecision.wait("no_candidates", details)
	var best: Dictionary = cands[0]
	for c in cands:
		if float(c["score"]) > float(best["score"]):
			best = c
	var ranked := cands.duplicate()
	ranked.sort_custom(func(x, y): return float(x["score"]) > float(y["score"])) # estable: orden de la vista en empates
	details["top"] = ranked.slice(0, TOP_N).map(func(c): return {"ability": c["ability"], "target": c["target"], "score": snappedf(float(c["score"]), 0.0001)})
	details["best_features"] = best["features"]
	if wait_below != null and float(best["score"]) < float(wait_below):
		return AIDecision.wait("reserve", details)
	return AIDecision.use(str(best["ability"]), [best["target"]], "scored", details)


func _features(view: Dictionary, aid: String, tid: String, tdict: Dictionary, ab: Dictionary) -> Dictionary:
	var ev := AIPredictor.evaluate(view, aid, tid)
	var rel := "self" if tid == view["self"]["id"] else str(tdict.get("relation", "enemy"))
	var hostile := rel == "enemy"
	var prof: Dictionary = ab["profile"]
	var has_dmg: bool = not (prof["damage"] as Array).is_empty()
	var has_heal: bool = not (prof["heals"] as Array).is_empty()
	var hp: Variant = tdict.get("hp", null)
	var hp_max: Variant = tdict.get("hp_max", null)
	var ratio := 1.0
	if hp != null and hp_max != null and float(hp_max) > 0.0:
		ratio = float(hp) / float(hp_max)
	var sign := 1.0 if hostile else -1.0
	var f := {}
	f["damage"] = sign * (clampf(float(ev["damage_total"]) / maxf(float(hp), 1.0), 0.0, 1.0) if hp != null else 0.0) if has_dmg else 0.0
	f["lethal"] = sign * (1.0 if bool(ev["lethal"]) else 0.0)
	f["lethal_potential"] = sign * (1.0 if bool(ev["lethal_potential"]) else 0.0)
	var heal_sign := -1.0 if hostile else 1.0
	f["heal"] = heal_sign * (clampf(float(ev["heal"]) / maxf(float(hp_max), 1.0), 0.0, 1.0) if hp_max != null else 0.0) if has_heal else 0.0
	f["need"] = (1.0 - ratio) if has_heal and not hostile else 0.0
	f["low_target"] = (1.0 - ratio) if has_dmg and hostile else 0.0
	var st: Dictionary = ev["statuses"]
	f["status"] = 1.0 if not (st["new_for_target"] as Array).is_empty() else 0.0
	f["hit"] = float(ev["hit_chance"]) if has_dmg else 0.0
	f["cost"] = float(ev["cost_fraction"])
	var ttt: Variant = ev["time_to_turn"]
	var interval := float(view["self"]["memory"].get("obs", {}).get(tid, {}).get("interval", 0.0))
	f["tempo"] = (1.0 - clampf(float(ttt) / interval, 0.0, 1.0)) if ttt != null and interval > 0.0 and hostile else 0.0
	f["reaction_risk"] = 1.0 if has_dmg and hostile and int(ev["reactions_seen"]) > 0 else 0.0
	return f
