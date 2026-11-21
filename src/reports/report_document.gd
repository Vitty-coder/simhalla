class_name ReportDocument
extends RefCounted
## Documento de presentacion derivado del MODELO de informe: una lista ordenada de bloques que consumen por igual
## los renderizadores Markdown y HTML (el JSON es el propio modelo). Asi los tres formatos salen del mismo modelo
## versionado y no pueden divergir en datos.
##
## Bloques: {t:"h", level, text} {t:"p", text} {t:"note", text} {t:"kv", rows:[[k,v]]} {t:"table", cols, rows, align}
##          {t:"bars", title, unit, items:[{label, value, lo?, hi?}], max} {t:"hist", title, bins:[{lo,hi,count}]} {t:"list", items}
## Todo el texto es DATO sin escapar: cada renderizador lo escapa (los nombres/etiquetas importados pueden ser hostiles).

var title: String = ""
var blocks: Array = []


static func num(v: Variant, decimals: int = 3) -> String:
	if v == null:
		return "—"
	if v is bool:
		return "si" if v else "no"
	if v is int:
		return str(v)
	if v is float:
		if is_nan(v) or is_inf(v):
			return "—"
		if floorf(v) == v and absf(v) < 1.0e12:
			return str(int(v))
		var t := String.num(v, decimals)
		if t.contains("."):
			t = t.rstrip("0").rstrip(".")
		return t
	return str(v)


static func pct(v: Variant) -> String:
	return "—" if v == null else num(float(v) * 100.0, 1) + " %"


static func ci(v: Variant, as_pct: bool = false) -> String:
	if v == null:
		return "—"
	var a: Array = v
	return "[%s, %s]" % [pct(a[0]) if as_pct else num(a[0]), pct(a[1]) if as_pct else num(a[1])]


func _h(level: int, text: String) -> void:
	blocks.append({"t": "h", "level": level, "text": text})


func _p(text: String) -> void:
	blocks.append({"t": "p", "text": text})


func _note(text: String) -> void:
	blocks.append({"t": "note", "text": text})


func _kv(rows: Array) -> void:
	blocks.append({"t": "kv", "rows": rows})


func _table(cols: Array, rows: Array, align: Array = []) -> void:
	if rows.is_empty():
		_note("(sin datos)")
		return
	blocks.append({"t": "table", "cols": cols, "rows": rows, "align": align})


static func from_model(m: Dictionary, with_measurement: bool = false) -> ReportDocument:
	var d := ReportDocument.new()
	if str(m.get("kind", "")) == "individual":
		d._individual(m)
	elif str(m.get("kind", "")) == "batch":
		d._batch(m, with_measurement)
	else:
		d.title = "Informe"
		d._note("modelo de informe desconocido")
	return d


# --- Individual ------------------------------------------------------------------------------------------------

func _individual(m: Dictionary) -> void:
	var meta: Dictionary = m["meta"]
	var r: Dictionary = m["result"]
	title = "Informe de combate (semilla %s)" % str(meta["seed"])
	_h(1, title)
	_kv([["Motor", meta["engine_version"]], ["Reglamento", "%s %s (%s)" % [meta["ruleset"]["id"], meta["ruleset"]["version"], str(meta["ruleset"]["hash"]).substr(0, 12)]],
		["Semilla", meta["seed"]], ["Huella del registro (log_hash)", meta["log_hash"]], ["Traza", meta["trace"]]])
	_h(2, "Resultado")
	var res_rows: Array = [["Resultado", r["outcome"]], ["Equipo ganador", r["winner_team"] if r["winner_team"] != "" else "—"], ["Causa", "%s (%s)" % [r["reason"], r["kind"]]]]
	if not (r["error"] as Dictionary).is_empty():
		res_rows.append(["Error tecnico", "%s: %s" % [r["error"].get("code", ""), r["error"].get("message", "")]])
	_kv(res_rows)
	var ents: Array = []
	for id in r["entities"]:
		ents.append([id, r["entities"][id]["team"], "si" if r["entities"][id]["alive"] else "no", num(r["entities"][id]["hp"])])
	_table(["Entidad", "Equipo", "Viva", "Vida final"], ents, ["l", "l", "l", "r"])
	_h(2, "Duracion")
	var du: Dictionary = m["duration"]
	_kv([["Tiempo virtual (ATB)", num(du["virtual_time"])], ["Turnos globales", du["turns_global"]], ["Acciones", du["actions"]], ["Eventos", du["events"]]])
	var trows: Array = []
	for id in du["turns_by_entity"]:
		trows.append([id, du["turns_by_entity"][id], du["turns_skipped_by_entity"].get(id, 0)])
	_table(["Entidad", "Turnos propios", "Omitidos"], trows, ["l", "r", "r"])
	_h(2, "Dano")
	var dm: Dictionary = m["damage"]
	var drows: Array = []
	for id in dm["by_entity"]:
		var e: Dictionary = dm["by_entity"][id]
		drows.append([id, num(e["dealt"]), num(e["taken"]), num(e["intended"]), num(e["premitigation"]), num(e["mitigated"]), num(e["absorbed_taken"]), num(e["overkill"]), num(e["reflected"])])
	_table(["Entidad", "Causado (efectivo)", "Recibido", "Intentado", "Premitigacion", "Mitigado", "Absorbido", "Sobreexceso", "Reflejado"], drows, ["l", "r", "r", "r", "r", "r", "r", "r", "r"])
	_note(str(dm["note"]))
	var items: Array = []
	for k in dm["by_type"]:
		items.append({"label": "tipo " + str(k), "value": float(dm["by_type"][k])})
	for k in dm["by_element"]:
		items.append({"label": "elemento " + str(k), "value": float(dm["by_element"][k])})
	if not items.is_empty():
		blocks.append({"t": "bars", "title": "Dano efectivo por tipo y elemento", "unit": "", "items": items})
	var src_rows: Array = []
	for s in dm["by_source_ability"]:
		for a in dm["by_source_ability"][s]:
			src_rows.append([s, a, num(dm["by_source_ability"][s][a])])
	_table(["Fuente", "Habilidad", "Dano efectivo"], src_rows, ["l", "l", "r"])
	if not (dm["absorbed_by"] as Dictionary).is_empty():
		_table(["Mitigacion por fuente", "Importe"], dm["absorbed_by"].keys().map(func(k): return [k, num(dm["absorbed_by"][k])]), ["l", "r"])
	_h(2, "Curacion")
	var hrows: Array = []
	for id in m["healing"]["by_entity"]:
		var h: Dictionary = m["healing"]["by_entity"][id]
		hrows.append([id, num(h["generated"]), num(h["effective"]), num(h["received"]), num(h["overheal"])])
	_table(["Entidad", "Generada", "Efectiva", "Recibida", "Desperdiciada (overheal)"], hrows, ["l", "r", "r", "r", "r"])
	_h(2, "Ataques")
	var arows: Array = []
	for id in m["attacks"]["by_entity"]:
		var a: Dictionary = m["attacks"]["by_entity"][id]
		arows.append([id, a["hits"], a["misses"], a["crits"], a["dodged"], pct(a["hit_rate"]), pct(a["crit_rate"])])
	_table(["Entidad", "Impactos", "Fallos", "Criticos", "Esquivas", "Tasa de impacto", "Tasa de critico"], arows, ["l", "r", "r", "r", "r", "r", "r"])
	_h(2, "Habilidades")
	var brows: Array = []
	for id in m["abilities"]["by_entity"]:
		for ab in m["abilities"]["by_entity"][id]:
			var x: Dictionary = m["abilities"]["by_entity"][id][ab]
			brows.append([id, ab, x["uses"], x["interrupted"], num(x["damage_effective"]), num(x["healing_effective"]), str(x["resources_spent"])])
	_table(["Entidad", "Habilidad", "Usos", "Interrumpidas", "Dano efectivo", "Curacion efectiva", "Recursos gastados"], brows, ["l", "l", "r", "r", "r", "r", "l"])
	_note(str(m["abilities"]["note"]))
	_h(2, "Recursos")
	var rrows: Array = []
	for id in m["resources"]["by_entity"]:
		for rid in m["resources"]["by_entity"][id]:
			var q: Dictionary = m["resources"]["by_entity"][id][rid]
			rrows.append([id, rid, num(q["initial"]), num(q["final"]), num(q["generated"]), num(q["consumed"]), q["limit_max_hits"], q["limit_min_hits"]])
	_table(["Entidad", "Recurso", "Inicial", "Final", "Generado", "Consumido", "Veces en maximo", "Veces en minimo"], rrows, ["l", "l", "r", "r", "r", "r", "r", "r"])
	_h(2, "Estados")
	var srows: Array = []
	for id in m["statuses"]["by_entity"]:
		for sid in m["statuses"]["by_entity"][id]:
			var s2: Dictionary = m["statuses"]["by_entity"][id][sid]
			srows.append([id, sid, s2["applications"], s2["rejected"], s2["max_stacks"], s2["removed"], s2["expired"], s2["dispelled"], num(s2["mean_duration"])])
	_table(["Afectado", "Estado", "Aplicaciones", "Rechazos", "Pilas max.", "Retirados", "Expirados", "Disipados", "Duracion media"], srows, ["l", "l", "r", "r", "r", "r", "r", "r", "r"])
	_h(2, "Defensas")
	var df: Dictionary = m["defenses"]
	var frows: Array = []
	for k in df["mitigation_by_source"]:
		frows.append([k, df["mitigation_by_source"][k]["count"], num(df["mitigation_by_source"][k]["amount"])])
	_table(["Fuente de mitigacion", "Veces", "Importe"], frows, ["l", "r", "r"])
	var prow: Array = []
	for k in df["parry_block"]:
		prow.append([k, df["parry_block"][k]["attempts"], df["parry_block"][k]["successes"]])
	_table(["Parada/bloqueo", "Intentos", "Exitos"], prow, ["l", "r", "r"])
	_h(2, "IA")
	var irows: Array = []
	for id in m["ai"]["by_entity"]:
		var i: Dictionary = m["ai"]["by_entity"][id]
		irows.append([id, i["decisions"], i["waits"], i["fallbacks"], i["rejected"], i["declined_reactions"], str(i["reasons"]), str(i["abilities"])])
	_table(["Entidad", "Decisiones", "Esperas", "Fallbacks", "Rechazadas", "Reacciones declinadas", "Motivos", "Habilidades elegidas"], irows)
	_h(2, "Aleatoriedad")
	var rn: Dictionary = m["randomness"]
	_kv([["Tiradas de impacto", rn["hit"]["rolls"]], ["Probabilidad media", pct(rn["hit"]["mean_chance"])], ["Impactos observados", pct(rn["hit"]["observed_rate"])],
		["Criticos (exitos)", rn["crit"]["successes"]]])
	var prc: Array = []
	for k in rn["proc"]:
		prc.append([k, rn["proc"][k]["rolls"], rn["proc"][k]["successes"], num(rn["proc"][k]["expected"])])
	_table(["Proc", "Tiradas", "Exitos", "Esperados"], prc, ["l", "r", "r", "r"])
	_note(str(rn["note"]))
	if m.has("balance"):
		var b: Dictionary = m["balance"]
		_h(2, "Equilibrio")
		for l in b["labels"]:
			_note(str(l))
		_kv([["Perfil", "%s %s" % [b["profile"]["id"], b["profile"]["version"]]], ["Modo", b["mode"]], ["Presupuesto", "%s (%s PC)" % [b["budget"]["id"], num(b["budget"]["points"])]],
			["Coste de creacion", num(b["creation_cost"])], ["Bruto / creditos", "%s / %s" % [num(b["gross"]), num(b["credits_applied"])]], ["Restante", num(b["remaining"])]])
		_table(["Componente", "Tipo", "Origen", "Regla", "Importe"], b["top_components"].map(func(c): return [c["id"], c["kind"], c["origin"], c["rule"], num(c["amount"])]), ["l", "l", "l", "l", "r"])
		if not b["discrepancies"].is_empty():
			blocks.append({"t": "list", "items": b["discrepancies"]})
	if not (m["metrics"] as Array).is_empty():
		_h(2, "Metricas de contenido")
		_table(["Metrica", "Tipo", "Unidad", "Total", "Veces", "Media", "Origen"], m["metrics"].map(func(x): return [x["name"], x["type"], x["unit"], num(x["total"]), x["count"], num(x["mean"]), x["origin"]]), ["l", "l", "l", "r", "r", "r", "l"])
	if m.has("history"):
		var hs: Dictionary = m["history"]
		_h(2, "Historial (%s)" % hs["mode"])
		_note("%s · %d eventos en este modo%s" % [str(hs["note"]), int(hs["total_in_mode"]), " (truncado)" if bool(hs["truncated"]) else ""])
		_table(["#", "t", "Evento", "Origen", "Destino", "Causa", "Datos"], hs["events"].map(func(e): return [e["id"], num(e["t"]), e["type"], e["source"], e["target"], e["cause"], str(e["data"])]), ["r", "r", "l", "l", "l", "r", "l"])
	_h(2, "Reproduccion")
	_kv([["Semilla", m["reproduce"]["seed"]], ["Version del motor", m["reproduce"]["engine_version"]], ["log_hash", m["reproduce"]["log_hash"]], ["Como", m["reproduce"]["how"]]])


# --- Masivo ----------------------------------------------------------------------------------------------------

func _batch(m: Dictionary, with_measurement: bool = false) -> void:
	var meta: Dictionary = m["meta"]
	var sm: Dictionary = m["sample"]
	title = "Informe de lote: %s" % str(meta["name"])
	_h(1, title)
	_kv([["Estado", meta["status"]], ["Motor", meta["engine_version"]], ["Semilla maestra", meta["master_seed"]], ["Modo de semillas", meta["seed_mode"]],
		["Repeticiones por escenario", meta["repetitions"]], ["Huella del plan", meta["plan_fingerprint"]], ["Huella del lote", meta["fingerprint"]]])
	_h(2, "Muestra")
	_kv([["Trabajos planificados", sm["total_jobs"]], ["Ejecutados", sm["executed"]], ["Pendientes", sm["pending"]], ["Resueltos (denominador de las tasas)", sm["finished"]],
		["Errores (abortos tecnicos y de preparacion, aparte)", sm["errors"]], ["Cancelados", sm["cancelled"]]])
	_h(2, "Configuracion")
	_table(["Escenario", "Etiqueta", "Parametros", "Lados", "Grupo", "Repeticiones"], meta["scenarios"].map(func(s): return [s["key"], s["label"], str(s["params"]), str(s["sides"]), s["group"], s["repetitions"]]))
	if not (m["ranking"] as Array).is_empty():
		_h(2, "Clasificacion")
		_table(["Contendiente", "Partidas", "Victorias", "Derrotas", "Empates", "Tasa de victoria", "IC95 Wilson", "Puntuacion"],
			m["ranking"].map(func(e): return [e["label"], e["games"], e["wins"], e["losses"], e["draws"], pct(e["win_rate"]["rate"]), ci(e["win_rate"]["wilson95"], true), num(e["score"])]), ["l", "r", "r", "r", "r", "r", "l", "r"])
		blocks.append({"t": "bars", "title": "Tasa de victoria (IC95 Wilson)", "unit": "%", "max": 1.0, "items": m["ranking"].map(func(e): return {"label": e["label"], "value": e["win_rate"]["rate"], "lo": e["win_rate"]["wilson95"][0] if e["win_rate"]["wilson95"] != null else null, "hi": e["win_rate"]["wilson95"][1] if e["win_rate"]["wilson95"] != null else null})})
	if not (m["matrix"]["cells"] as Array).is_empty():
		_h(2, "Enfrentamientos (favorables / desfavorables)")
		_table(["Fila", "Contra", "Partidas", "Victorias", "Empates", "Tasa", "IC95 Wilson"], m["matrix"]["cells"].map(func(c): return [c["row"], c["col"], c["games"], c["wins"], c["draws"], pct(c["win_rate"]["rate"]), ci(c["win_rate"]["wilson95"], true)]), ["l", "l", "r", "r", "r", "r", "l"])
		_note(str(m["matrix"]["note"]))
	for s in m["scenarios"]:
		_scenario(s)
	if not (m["comparisons"] as Array).is_empty():
		_h(2, "Comparaciones entre variantes")
		_note("Resultado comparado: " + str(m["comparisons"][0]["outcome"]))
		var rows: Array = []
		for c in m["comparisons"]:
			var diff: String = "—"
			var cis: String = "—"
			var extra: String = ""
			if c.has("paired") and c["paired"].has("diff"):
				diff = num(c["paired"]["diff"])
				cis = ci(c["paired"]["ci95"])
				extra = "n=%d parejas; solo A %d / solo B %d" % [c["paired"]["n_pairs"], c["paired"]["a_only"], c["paired"]["b_only"]]
			elif c["independent"] != null:
				diff = num(c["independent"]["diff"])
				cis = "[%s, %s]" % [num(c["independent"]["lo"]), num(c["independent"]["hi"])]
			rows.append([c["group"], c["a_label"], pct(c["a_rate"]["rate"]), c["b_label"], pct(c["b_rate"]["rate"]), diff, cis, c["method"], extra])
		_table(["Grupo", "A", "Tasa A", "B", "Tasa B", "Diferencia A-B", "IC95", "Metodo", "Detalle"], rows)
	_h(2, "Metodologia")
	blocks.append({"t": "list", "items": m["methods"].values()})
	if with_measurement:
		_h(2, "Medicion")
		_note("%s: %s" % [str(m["measurement"]["note"]), str(m["measurement"]["perf"])])


func _scenario(s: Dictionary) -> void:
	_h(2, "Escenario: %s" % str(s["label"]))
	var sp: Dictionary = s["sample"]
	_kv([["Clave", s["key"]], ["Parametros", str(s["params"])], ["n total", sp["n_total"]], ["Resueltos (n)", sp["finished"]], ["Abortos tecnicos", sp["aborted"]],
		["Errores de preparacion", sp["setup_errors"]], ["Cancelados", sp["cancelled"]]])
	var rows: Array = []
	for l in s["outcomes"]["wins"]:
		var w: Dictionary = s["outcomes"]["wins"][l]
		rows.append([l, "victorias", w["k"], w["n"], pct(w["rate"]), ci(w["wilson95"], true)])
	var d: Dictionary = s["outcomes"]["draws"]
	rows.append(["—", "empates", d["k"], d["n"], pct(d["rate"]), ci(d["wilson95"], true)])
	_table(["Contendiente", "Resultado", "k", "n", "Tasa", "IC95 Wilson"], rows, ["l", "l", "r", "r", "r", "l"])
	var bars: Array = []
	for l in s["outcomes"]["wins"]:
		var w2: Dictionary = s["outcomes"]["wins"][l]
		bars.append({"label": l, "value": w2["rate"], "lo": w2["wilson95"][0] if w2["wilson95"] != null else null, "hi": w2["wilson95"][1] if w2["wilson95"] != null else null})
	blocks.append({"t": "bars", "title": "Victorias (IC95 Wilson)", "unit": "%", "max": 1.0, "items": bars})
	var drows: Array = []
	for f in ["turns", "end_time", "events"]:
		var q: Dictionary = s["distributions"][f]
		if int(q["n"]) > 0:
			drows.append([f, q["n"], num(q["mean"]), ci(q["ci95"]), num(q["sd"]), num(q["median"]), num(q["q1"]), num(q["q3"]), num(q["min"]), num(q["max"])])
	_table(["Metrica", "n", "Media", "IC95 media", "Desv. tipica", "Mediana", "Q1", "Q3", "Min", "Max"], drows, ["l", "r", "r", "l", "r", "r", "r", "r", "r", "r"])
	if int(s["distributions"]["turns"]["n"]) > 0:
		blocks.append({"t": "hist", "title": "Distribucion de turnos", "bins": s["distributions"]["turns"]["histogram"]})
	var dm: Array = []
	for l in s["damage_per_battle"]:
		var a: Dictionary = s["damage_per_battle"][l]
		var h: Dictionary = s["healing_per_battle"][l]
		if int(a["n"]) > 0:
			dm.append([l, num(a["mean"]), ci(a["ci95"]), num(a["median"]), num(h["mean"]), ci(h["ci95"])])
	_table(["Contendiente", "Dano medio/combate", "IC95", "Mediana", "Curacion media", "IC95"], dm, ["l", "r", "l", "r", "r", "l"])
	var ab: Array = []
	for l in s["abilities"]:
		for a in s["abilities"][l]:
			var x: Dictionary = s["abilities"][l][a]
			ab.append([l, a, x["battles_used"], pct(x["usage_rate"]["rate"]), num(x["mean_uses"]), num(x["mean_damage"]), pct(x["win_rate_when_used"]["rate"]), pct(x["win_rate_when_unused"]["rate"])])
	if not ab.is_empty():
		_table(["Contendiente", "Habilidad", "Combates con uso", "Uso", "Usos medios", "Dano medio", "Victoria si se usa", "Victoria si no"], ab, ["l", "l", "r", "r", "r", "r", "r", "r"])
		_note("Asociacion observada, no causalidad: una habilidad usada por quien va ganando no implica que cause la victoria.")
	var cm: Array = []
	for k in s["custom_metrics"]:
		var q2: Dictionary = s["custom_metrics"][k]
		cm.append([k, q2["type"], q2["unit"], q2["n"], num(q2["mean"]), ci(q2["ci95"]), num(q2["median"])])
	if not cm.is_empty():
		_table(["Metrica", "Tipo", "Unidad", "n", "Media/combate", "IC95", "Mediana"], cm, ["l", "l", "l", "r", "r", "l", "r"])
	if not (s["errors"] as Array).is_empty():
		_h(3, "Errores (aparte de los resultados)")
		_table(["Estado", "Mensaje", "Veces"], s["errors"].map(func(e): return [e["status"], e["message"], e["count"]]), ["l", "l", "r"])
	_table(["Trabajo", "Repeticion", "Semilla", "Estado", "log_hash"], s["jobs"].map(func(j): return [j["index"], j["repetition"], j["seed"], j["status"], j["log_hash"]]), ["r", "r", "r", "l", "l"])
