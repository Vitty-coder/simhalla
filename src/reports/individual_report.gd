class_name IndividualReport
extends RefCounted
## Informe INDIVIDUAL de un combate (PROJECT.md §14.1): modelo estructurado y versionado (`simhalla.report/1`) calculado
## ESCANEANDO el registro de eventos (traza completa) y el resultado. Sin marcas de tiempo ni nada no reproducible:
## el mismo combate (version, contenido, reglas, configuracion y semilla) da exactamente el mismo informe.
##
## Secciones: result, duration, damage (causado/recibido/intentado/premitigacion/mitigado/absorbido/sobreexceso, por tipo,
## elemento y fuente), healing, attacks, abilities, resources, statuses, defenses, ai, randomness, balance (opcional),
## metrics (de contenido), history (cronologia con relaciones causales) y reproduce. El dano intentado, la premitigacion, el
## efectivo y el sobreexceso se separan para evitar doble conteo. La atribucion a una habilidad sigue la cadena causal
## (el evento `action_started` ancestro); sin accion (periodicos, reflejos) se agrupa en "(otros)".
##
## options: {"config": DuelRunner config (para reproducir), "balance": BalanceReport.to_dict(),
##           "history": "none"|"summary"|"full" (por defecto summary), "history_limit": 200}

const SCHEMA := "simhalla.report/1"
const OTHER := "(otros)"
const MILESTONES := ["combat_started", "turn_started", "action_selected", "action_resolved", "damage_dealt", "heal_done", "status_gained",
	"status_removed", "status_expired", "death", "reaction_triggered", "limit_reached", "error", "combat_ended"]


## {"ok", "errors", "report"}.
static func build(engine: CombatEngine, options: Dictionary = {}) -> Dictionary:
	if engine.log.level != EventLog.TraceLevel.FULL:
		return {"ok": false, "errors": ["el informe individual requiere traza completa (TraceLevel.FULL)"], "report": {}}
	if engine.result == null:
		return {"ok": false, "errors": ["el combate no ha terminado"], "report": {}}
	return {"ok": true, "errors": [], "report": build_from(engine.log.events, engine.result, options)}


static func build_from(events: Array, result: CombatResult, options: Dictionary = {}) -> Dictionary:
	var idx := {}
	for ev in events:
		idx[int(ev["id"])] = ev
	var ctx := {"idx": idx}
	var m := {"schema": SCHEMA, "kind": "individual"}
	m["meta"] = _meta(events, result)
	m["result"] = {"outcome": result.outcome, "winner_team": result.winner_team, "reason": result.reason, "kind": result.kind, "error": result.error,
		"entities": result.entities}
	m["duration"] = _duration(events, result)
	var dmg := _damage(events, ctx)
	m["damage"] = dmg
	m["healing"] = _healing(events)
	m["attacks"] = _attacks(events)
	m["abilities"] = _abilities(events, ctx)
	m["resources"] = _resources(events)
	m["statuses"] = _statuses(events)
	m["defenses"] = _defenses(events, ctx)
	m["ai"] = _ai(events)
	m["randomness"] = _randomness(events)
	if options.has("balance"):
		m["balance"] = _balance(options["balance"])
	m["metrics"] = _metrics(result.metrics)
	var hist := str(options.get("history", "summary"))
	if hist != "none":
		m["history"] = _history(events, hist, int(options.get("history_limit", 200)))
	m["reproduce"] = _reproduce(result, options)
	return m


# --- Secciones -------------------------------------------------------------------------------------------------

static func _meta(events: Array, r: CombatResult) -> Dictionary:
	var started: Dictionary = {}
	for ev in events:
		if ev["type"] == "combat_started":
			started = ev
			break
	var ents: Array = []
	var overrides: Dictionary = {}
	if not started.is_empty():
		overrides = started["data"].get("initial_overrides", {})
		for e in started["data"].get("entities", []):
			ents.append({"id": e["id"], "team": e["team"], "ai": e["ai"], "abilities": e["abilities"], "hp_max": e["hp_max"], "stats": e["stats"],
				"content": e.get("content", {}), "scripts": e.get("scripts", {})})
	return {"engine_version": r.engine_version, "ruleset": {"id": r.ruleset_id, "version": r.ruleset_version, "hash": r.ruleset_hash},
		"seed": str(r.seed_value), "log_hash": r.log_hash, "trace": "full", "entities": ents, "initial_overrides": overrides}


static func _duration(events: Array, r: CombatResult) -> Dictionary:
	var turns := {}
	var skipped := {}
	var by_type := {}
	for ev in events:
		by_type[ev["type"]] = int(by_type.get(ev["type"], 0)) + 1
		if ev["type"] == "turn_started":
			turns[ev["source"]] = int(turns.get(ev["source"], 0)) + 1
		elif ev["type"] == "turn_skipped":
			skipped[ev["source"]] = int(skipped.get(ev["source"], 0)) + 1
	return {"virtual_time": r.end_time, "turns_global": r.turns, "turns_by_entity": turns, "turns_skipped_by_entity": skipped, "actions": r.actions,
		"events": r.events, "events_by_type": by_type}


static func _ability_of(ev: Dictionary, ctx: Dictionary) -> String:
	var idx: Dictionary = ctx["idx"]
	var cur: int = int(ev["cause"])
	var guard := 0
	while idx.has(cur) and guard < 1000:
		guard += 1
		var e: Dictionary = idx[cur]
		if e["type"] == "action_started":
			return str(e["data"].get("ability", OTHER))
		cur = int(e["cause"])
	return OTHER


static func _ent(d: Dictionary, id: String, template: Dictionary) -> Dictionary:
	if not d.has(id):
		d[id] = template.duplicate(true)
	return d[id]


static func _bump(d: Dictionary, key: String, amount: float) -> void:
	d[key] = float(d.get(key, 0.0)) + amount


static func _damage(events: Array, ctx: Dictionary) -> Dictionary:
	var by_entity := {}
	var by_type := {}
	var by_element := {}
	var by_source := {}
	var matrix := {}
	var absorbed := {}
	var tpl := {"dealt": 0.0, "taken": 0.0, "intended": 0.0, "premitigation": 0.0, "mitigated": 0.0, "overkill": 0.0, "reflected": 0.0, "absorbed_taken": 0.0}
	for ev in events:
		match ev["type"]:
			"damage_dealt":
				var d: Dictionary = ev["data"]
				var src: String = ev["source"]
				var tgt: String = ev["target"]
				var a := _ent(by_entity, src, tpl)
				var t := _ent(by_entity, tgt, tpl)
				a["dealt"] += float(d["applied"])
				a["intended"] += float(d["intended"])
				a["premitigation"] += float(d["premitigation"])
				a["mitigated"] += float(d["mitigated"])
				a["overkill"] += float(d["overkill"])
				t["taken"] += float(d["applied"])
				if bool(d.get("reflected", false)):
					a["reflected"] += float(d["applied"])
				var ty := str(d["damage_type"])
				_bump(by_type, ty, float(d["applied"]))
				var el := str(d.get("element", ""))
				_bump(by_element, el if el != "" else "(sin elemento)", float(d["applied"]))
				var ab := _ability_of(ev, ctx)
				if not by_source.has(src):
					by_source[src] = {}
				_bump(by_source[src], ab, float(d["applied"]))
				if not matrix.has(src):
					matrix[src] = {}
				_bump(matrix[src], tgt, float(d["applied"]))
			"event_modified":
				var md: Dictionary = ev["data"]
				var target_ev: Variant = ctx["idx"].get(int(md["event"]), null)
				if target_ev != null and target_ev["type"] == "damage_pre" and str(md["key"]) == "amount":
					var cut := float(md["old"]) - float(md["new"])
					if cut > 0.0:
						_bump(absorbed, str(ev["source"]), cut)
						_ent(by_entity, str(ev["target"]), tpl)["absorbed_taken"] += cut
	var total_absorbed := 0.0
	for k in absorbed:
		total_absorbed += float(absorbed[k])
	return {"by_entity": by_entity, "by_type": by_type, "by_element": by_element, "by_source_ability": by_source, "matrix": matrix,
		"absorbed_by": absorbed, "absorbed_total": total_absorbed,
		"note": "dealt = dano efectivo aplicado; intended/premitigation/mitigated/overkill se separan para no contar dos veces"}


static func _healing(events: Array) -> Dictionary:
	var by := {}
	var tpl := {"generated": 0.0, "effective": 0.0, "received": 0.0, "overheal": 0.0}
	for ev in events:
		if ev["type"] == "heal_done":
			var d: Dictionary = ev["data"]
			var a := _ent(by, str(ev["source"]), tpl)
			a["generated"] += float(d["amount"])
			a["effective"] += float(d["applied"])
			a["overheal"] += float(d["overheal"])
			_ent(by, str(ev["target"]), tpl)["received"] += float(d["applied"])
	return {"by_entity": by}


static func _attacks(events: Array) -> Dictionary:
	var by := {}
	var tpl := {"hits": 0, "misses": 0, "crits": 0, "dodged": 0}
	for ev in events:
		match ev["type"]:
			"hit":
				_ent(by, str(ev["source"]), tpl)["hits"] += 1
			"miss":
				_ent(by, str(ev["source"]), tpl)["misses"] += 1
				_ent(by, str(ev["target"]), tpl)["dodged"] += 1
			"crit":
				if str(ev["data"].get("kind", "")) != "heal":
					_ent(by, str(ev["source"]), tpl)["crits"] += 1
	for id in by:
		var a: Dictionary = by[id]
		var n := int(a["hits"]) + int(a["misses"])
		a["attacks"] = n
		a["hit_rate"] = float(a["hits"]) / float(n) if n > 0 else null
		a["crit_rate"] = float(a["crits"]) / float(a["hits"]) if int(a["hits"]) > 0 else null
	return {"by_entity": by}


static func _abilities(events: Array, ctx: Dictionary) -> Dictionary:
	var by := {}
	var tpl := {"uses": 0, "interrupted": 0, "damage_effective": 0.0, "healing_effective": 0.0, "resources_spent": {}}
	var started_ability := {}
	for ev in events:
		match ev["type"]:
			"action_resolved":
				_ability_entry(by, str(ev["source"]), str(ev["data"].get("ability", "?")), tpl)["uses"] += 1
			"action_interrupted":
				_ability_entry(by, str(ev["source"]), str(ev["data"].get("ability", "?")), tpl)["interrupted"] += 1
			"damage_dealt":
				_ability_entry(by, str(ev["source"]), _ability_of(ev, ctx), tpl)["damage_effective"] += float(ev["data"]["applied"])
			"heal_done":
				_ability_entry(by, str(ev["source"]), _ability_of(ev, ctx), tpl)["healing_effective"] += float(ev["data"]["applied"])
			"resource_changed":
				if str(ev["data"].get("reason", "")) == "cost":
					var e := _ability_entry(by, str(ev["source"]), _ability_of(ev, ctx), tpl)
					_bump(e["resources_spent"], str(ev["data"]["resource"]), -float(ev["data"]["delta"]))
	return {"by_entity": by, "note": "contribucion OBSERVADA (atribucion causal): no implica causalidad de la victoria"}


static func _ability_entry(by: Dictionary, entity: String, ability: String, tpl: Dictionary) -> Dictionary:
	if not by.has(entity):
		by[entity] = {}
	return _ent(by[entity], ability, tpl)


static func _resources(events: Array) -> Dictionary:
	var by := {}
	for ev in events:
		match ev["type"]:
			"resource_changed":
				var d: Dictionary = ev["data"]
				var ent: String = ev["source"]
				if not by.has(ent):
					by[ent] = {}
				var r := _ent(by[ent], str(d["resource"]), {"generated": 0.0, "consumed": 0.0, "by_reason": {}, "initial": d["old"], "final": d["new"], "limit_max_hits": 0, "limit_min_hits": 0})
				var delta := float(d["delta"])
				if delta > 0.0:
					r["generated"] += delta
				else:
					r["consumed"] += -delta
				_bump(r["by_reason"], str(d.get("reason", "?")), delta)
				r["final"] = d["new"]
			"resource_limit":
				var d2: Dictionary = ev["data"]
				var ent2: String = ev["source"]
				if by.has(ent2) and by[ent2].has(str(d2["resource"])):
					by[ent2][str(d2["resource"])]["limit_max_hits" if str(d2["limit"]) == "max" else "limit_min_hits"] += 1
	return {"by_entity": by, "note": "desperdicio = veces que un recurso toco su maximo (resource_limit); la cantidad exacta desperdiciada no se registra"}


static func _statuses(events: Array) -> Dictionary:
	var by := {}
	var starts := {}
	var tpl := {"applications": 0, "rejected": 0, "max_stacks": 0, "removed": 0, "expired": 0, "dispelled": 0, "durations": []}
	for ev in events:
		var t: String = ev["type"]
		if t == "status_gained" or t == "status_rejected" or t == "status_removed" or t == "status_expired" or t == "status_changed":
			var holder := str(ev["target"])
			var sid := str(ev["data"].get("status", "?"))
			if not by.has(holder):
				by[holder] = {}
			var s := _ent(by[holder], sid, tpl)
			var key := holder + "|" + sid
			match t:
				"status_gained":
					s["applications"] += 1
					s["max_stacks"] = maxi(int(s["max_stacks"]), int(ev["data"].get("stacks", 1)))
					if not starts.has(key):
						starts[key] = []
					starts[key].append(float(ev["time"]))
				"status_rejected":
					s["rejected"] += 1
				"status_changed":
					s["max_stacks"] = maxi(int(s["max_stacks"]), int(ev["data"].get("stacks", 0)))
				_:
					if t == "status_expired":
						s["expired"] += 1
					else:
						s["removed"] += 1
						if str(ev["data"].get("reason", "")) == "dispelled":
							s["dispelled"] += 1
					if starts.has(key) and not (starts[key] as Array).is_empty():
						(s["durations"] as Array).append((float(ev["time"]) - float(starts[key].pop_front())) / float(Ruleset.TIME_SCALE))
	for h in by:
		for sid in by[h]:
			var ds: Array = by[h][sid]["durations"]
			by[h][sid]["mean_duration"] = Stats.mean(ds) if not ds.is_empty() else null
			by[h][sid].erase("durations")
	return {"by_entity": by, "note": "duracion = tiempo virtual entre aplicacion y retirada (emparejadas en orden); aproximada con varias instancias"}


static func _defenses(events: Array, ctx: Dictionary) -> Dictionary:
	var absorbed := {}
	var procs := {}
	var cancelled := {}
	var tpl := {"count": 0, "amount": 0.0}
	for ev in events:
		match ev["type"]:
			"event_modified":
				var md: Dictionary = ev["data"]
				var te: Variant = ctx["idx"].get(int(md["event"]), null)
				if te != null and te["type"] == "damage_pre" and str(md["key"]) == "amount":
					var e := _ent(absorbed, str(ev["source"]), tpl)
					e["count"] += 1
					e["amount"] += float(md["old"]) - float(md["new"])
			"proc":
				var pd: Dictionary = ev["data"]
				if ["parry", "block"].has(str(pd["effect"])):
					var p := _ent(procs, str(pd["effect"]), {"attempts": 0, "successes": 0})
					p["attempts"] += 1
					p["successes"] += 1 if bool(pd["success"]) else 0
			"event_cancelled":
				var cd: Dictionary = ev["data"]
				var c := _ent(cancelled, str(cd["type"]), {"count": 0, "by": {}})
				c["count"] += 1
				c["by"][str(ev["source"])] = int(c["by"].get(str(ev["source"]), 0)) + 1
	return {"mitigation_by_source": absorbed, "parry_block": procs, "cancelled_events": cancelled}


static func _ai(events: Array) -> Dictionary:
	var by := {}
	var tpl := {"decisions": 0, "waits": 0, "abilities": {}, "reasons": {}, "fallbacks": 0, "rejected": 0, "declined_reactions": 0, "candidates_mean": null, "_cand_n": 0, "_cand_sum": 0.0}
	for ev in events:
		var src := str(ev["source"])
		match ev["type"]:
			"action_selected":
				var a := _ent(by, src, tpl)
				a["decisions"] += 1
				var d: Dictionary = ev["data"]
				if str(d.get("kind", "")) == "wait":
					a["waits"] += 1
				else:
					a["abilities"][str(d.get("ability", "?"))] = int(a["abilities"].get(str(d.get("ability", "?")), 0)) + 1
				var reason := str(d.get("reason", "?"))
				a["reasons"][reason] = int(a["reasons"].get(reason, 0)) + 1
				var det: Dictionary = d.get("details", {}) if d.get("details", {}) is Dictionary else {}
				if det.has("candidates_total"):
					a["_cand_n"] += 1
					a["_cand_sum"] += float(det["candidates_total"])
			"ai_fallback":
				_ent(by, src, tpl)["fallbacks"] += 1
			"action_rejected":
				_ent(by, src, tpl)["rejected"] += 1
			"reaction_declined":
				_ent(by, src, tpl)["declined_reactions"] += 1
	for id in by:
		var a2: Dictionary = by[id]
		if int(a2["_cand_n"]) > 0:
			a2["candidates_mean"] = float(a2["_cand_sum"]) / float(a2["_cand_n"])
		a2.erase("_cand_n")
		a2.erase("_cand_sum")
	return {"by_entity": by}


static func _randomness(events: Array) -> Dictionary:
	var hit := {"rolls": 0, "successes": 0, "expected": 0.0}
	var crit := {"successes": 0, "expected_sum": 0.0}
	var proc := {}
	for ev in events:
		match ev["type"]:
			"hit", "miss":
				if not bool(ev["data"].get("forced", false)):
					hit["rolls"] += 1
					hit["expected"] += float(ev["data"]["chance"])
					hit["successes"] += 1 if ev["type"] == "hit" else 0
			"crit":
				crit["successes"] += 1
				crit["expected_sum"] += float(ev["data"].get("chance", 0.0))
			"proc":
				var p := _ent(proc, str(ev["data"]["effect"]), {"rolls": 0, "successes": 0, "expected": 0.0})
				p["rolls"] += 1
				p["expected"] += float(ev["data"]["chance"])
				p["successes"] += 1 if bool(ev["data"]["success"]) else 0
	hit["mean_chance"] = float(hit["expected"]) / float(hit["rolls"]) if int(hit["rolls"]) > 0 else null
	hit["observed_rate"] = float(hit["successes"]) / float(hit["rolls"]) if int(hit["rolls"]) > 0 else null
	return {"hit": hit, "crit": crit, "proc": proc, "note": "`expected` = suma de probabilidades; comparelo con lo observado para detectar calibraciones raras"}


static func _balance(b: Dictionary) -> Dictionary:
	var top: Array = (b.get("items", []) as Array).filter(func(i): return bool(i["counted"])).duplicate()
	top.sort_custom(func(x, y): return absf(float(x["amount"])) > absf(float(y["amount"])))
	var discrepancies: Array = []
	if not bool(b.get("within_budget", true)):
		discrepancies.append("excede el presupuesto '%s' (%s PC)" % [str(b["budget"]["id"]), str(b["budget"]["points"])])
	for u in b.get("unevaluable", []):
		discrepancies.append("no evaluable: %s (%s)" % [str(u["id"]), str(u["reason"])])
	for e in b.get("technical_errors", []):
		discrepancies.append("error tecnico: %s" % str(e))
	return {"profile": b["profile"], "mode": b["mode"], "budget": b["budget"], "creation_cost": b["creation_cost"], "gross": b["gross"],
		"credits_applied": b["credits_applied"], "remaining": b["remaining"], "labels": b["labels"], "note": b.get("note", ""),
		"top_components": top.slice(0, 10).map(func(i): return {"id": i["id"], "kind": i["kind"], "origin": i["origin"], "rule": i["rule"], "amount": i["amount"]}),
		"items": b.get("items", []), "discrepancies": discrepancies}


static func _metrics(raw: Dictionary) -> Array:
	var out: Array = []
	var names: Array = raw.keys()
	names.sort()
	for n in names:
		var m: Dictionary = raw[n]
		out.append({"name": n, "type": "sum", "unit": "", "origin": "contenido (operacion metric)", "total": m["total"], "count": m["count"],
			"mean": float(m["total"]) / float(m["count"]) if int(m["count"]) > 0 else null, "by_entity": m.get("by_entity", {}),
			"aggregation": "suma por combate; media por lote"})
	return out


static func _history(events: Array, mode: String, limit: int) -> Dictionary:
	var out: Array = []
	var total := 0
	for ev in events:
		if mode == "summary" and not MILESTONES.has(str(ev["type"])):
			continue
		total += 1
		if out.size() < (limit if mode == "summary" else 100000):
			out.append({"id": ev["id"], "t": float(ev["time"]) / float(Ruleset.TIME_SCALE), "type": ev["type"], "source": ev["source"], "target": ev["target"],
				"cause": ev["cause"], "data": _brief(ev["data"], ev["type"])})
	return {"mode": mode, "events": out, "total_in_mode": total, "truncated": total > out.size(), "note": "`cause` enlaza cada evento con el que lo origino (0 = raiz)"}


static func _brief(d: Dictionary, type: String) -> Dictionary:
	if type == "combat_started":
		return {"seed": str(d.get("seed")), "entities": (d.get("entities", []) as Array).map(func(e): return e["id"])}
	var out := {}
	for k in d:
		if d[k] is float or d[k] is int or d[k] is bool or (d[k] is String and (d[k] as String).length() <= 80):
			out[k] = d[k]
	return out


static func _reproduce(r: CombatResult, options: Dictionary) -> Dictionary:
	var out := {"seed": str(r.seed_value), "engine_version": r.engine_version, "ruleset_hash": r.ruleset_hash, "log_hash": r.log_hash,
		"how": "ejecutar DuelRunner.run(config) con esta configuracion y comprobar que log_hash coincide (misma version del motor y del contenido)"}
	if options.has("config"):
		var c: Dictionary = (options["config"] as Dictionary).duplicate(true)
		c.erase("trace")
		if c.has("seed"):
			c["seed"] = str(c["seed"]) # texto: una semilla de 64 bits no cabe en un numero JSON sin perder precision
		out["config"] = c
	return out


## Comprobaciones de coherencia interna (los datos del informe cuadran entre si). Devuelve la lista de fallos.
static func verify_invariants(m: Dictionary) -> Array:
	var errs: Array = []
	var by: Dictionary = m["damage"]["by_entity"]
	var dealt := 0.0
	var taken := 0.0
	for id in by:
		dealt += float(by[id]["dealt"])
		taken += float(by[id]["taken"])
	if absf(dealt - taken) > 1e-6:
		errs.append("dano causado (%s) != dano recibido (%s)" % [str(dealt), str(taken)])
	var by_type_total := 0.0
	for k in m["damage"]["by_type"]:
		by_type_total += float(m["damage"]["by_type"][k])
	if absf(by_type_total - dealt) > 1e-6:
		errs.append("el dano por tipo no suma el total")
	var src_total := 0.0
	for s in m["damage"]["by_source_ability"]:
		for a in m["damage"]["by_source_ability"][s]:
			src_total += float(m["damage"]["by_source_ability"][s][a])
	if absf(src_total - dealt) > 1e-6:
		errs.append("el dano por fuente/habilidad no suma el total")
	var heal_eff := 0.0
	var heal_rec := 0.0
	for id in m["healing"]["by_entity"]:
		heal_eff += float(m["healing"]["by_entity"][id]["effective"])
		heal_rec += float(m["healing"]["by_entity"][id]["received"])
	if absf(heal_eff - heal_rec) > 1e-6:
		errs.append("curacion efectiva != curacion recibida")
	for id in m["attacks"]["by_entity"]:
		var a: Dictionary = m["attacks"]["by_entity"][id]
		if int(a["hits"]) + int(a["misses"]) != int(a["attacks"]):
			errs.append("impactos + fallos != ataques (%s)" % id)
	return errs
