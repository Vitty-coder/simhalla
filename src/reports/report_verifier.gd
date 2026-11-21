class_name ReportVerifier
extends RefCounted
## Verificacion de informes: "datos consistentes y reproducibles desde los informes" (hoja de ruta, fase 8).
##  - `check_individual` / `check_batch`: coherencia INTERNA (las cifras cuadran entre si; las tasas y los intervalos se recalculan).
##  - `verify_batch(modelo, lote)`: recalcula el informe desde los registros del lote y exige el mismo contenido.
##  - `reproduce_individual(modelo)`: re-ejecuta la configuracion guardada y exige el mismo log_hash y el mismo informe.
## Devuelven listas de discrepancias (vacia = correcto).

static func check_individual(m: Dictionary) -> Array:
	return IndividualReport.verify_invariants(m)


static func check_batch(m: Dictionary) -> Array:
	var errs: Array = []
	var total_fin := 0
	var total_err := 0
	var total_can := 0
	for s in m["scenarios"]:
		var sp: Dictionary = s["sample"]
		var n: int = sp["finished"]
		total_fin += n
		total_err += int(sp["errors"])
		total_can += int(sp["cancelled"])
		var k := 0
		for l in s["outcomes"]["wins"]:
			var w: Dictionary = s["outcomes"]["wins"][l]
			k += int(w["k"])
			if int(w["n"]) != n:
				errs.append("%s: el denominador de %s (%d) != resueltos (%d)" % [s["key"], l, int(w["n"]), n])
			errs.append_array(_check_rate(w, "%s/%s" % [s["key"], l]))
		k += int(s["outcomes"]["draws"]["k"])
		if k != n:
			errs.append("%s: victorias + empates (%d) != resueltos (%d)" % [s["key"], k, n])
		errs.append_array(_check_rate(s["outcomes"]["draws"], "%s/empates" % s["key"]))
		if int(sp["n_total"]) != n + int(sp["errors"]) + int(sp["cancelled"]):
			errs.append("%s: n_total != resueltos + errores + cancelados" % s["key"])
		for f in ["turns", "end_time", "events"]:
			if int(s["distributions"][f]["n"]) != n:
				errs.append("%s: la distribucion %s tiene n=%d (esperado %d)" % [s["key"], f, int(s["distributions"][f]["n"]), n])
			var hist: Array = s["distributions"][f].get("histogram", [])
			var hn := 0
			for b in hist:
				hn += int(b["count"])
			if n > 0 and hn != n:
				errs.append("%s: el histograma de %s suma %d (esperado %d)" % [s["key"], f, hn, n])
	var sm: Dictionary = m["sample"]
	if int(sm["finished"]) != total_fin or int(sm["errors"]) != total_err or int(sm["cancelled"]) != total_can:
		errs.append("la muestra global no suma los escenarios")
	if int(sm["executed"]) != total_fin + total_err + total_can:
		errs.append("ejecutados != resueltos + errores + cancelados")
	var cells := {}
	for c in m["matrix"]["cells"]:
		cells["%s|%s" % [c["row"], c["col"]]] = c
	for key in cells:
		var c: Dictionary = cells[key]
		var rev: Variant = cells.get("%s|%s" % [c["col"], c["row"]], null)
		if rev == null:
			errs.append("matriz: falta la celda simetrica de %s" % key)
			continue
		if int(c["games"]) != int(rev["games"]):
			errs.append("matriz: partidas asimetricas en %s" % key)
		if int(c["wins"]) + int(rev["wins"]) + int(c["draws"]) != int(c["games"]):
			errs.append("matriz: victorias + derrotas + empates != partidas en %s" % key)
	for e in m["ranking"]:
		if int(e["wins"]) + int(e["losses"]) + int(e["draws"]) != int(e["games"]):
			errs.append("clasificacion: %s no suma sus partidas" % e["label"])
	return errs


static func _check_rate(r: Dictionary, where: String) -> Array:
	var errs: Array = []
	var n: int = r["n"]
	if n > 0:
		if absf(float(r["rate"]) - float(r["k"]) / float(n)) > 1e-12:
			errs.append("%s: tasa != k/n" % where)
		var w: Variant = Stats.wilson(int(r["k"]), n)
		var got: Variant = r["wilson95"]
		if got == null or absf(float(got[0]) - float(w[0])) > 1e-9 or absf(float(got[1]) - float(w[1])) > 1e-9:
			errs.append("%s: el intervalo de Wilson no coincide" % where)
	return errs


## Recalcula el informe desde el lote y compara el modelo (sin `measurement`). Devuelve discrepancias.
static func verify_batch(model: Dictionary, res: BatchResult, options: Dictionary = {}) -> Array:
	var fresh := BatchReport.build(res, options)
	var a := ReportExporter.content_hash(model)
	var b := ReportExporter.content_hash(fresh)
	if a == b:
		return []
	var errs: Array = ["el informe no coincide con el recalculado desde los registros del lote (%s != %s)" % [a.substr(0, 12), b.substr(0, 12)]]
	for k in fresh:
		if k != "measurement" and JSON.stringify(fresh[k], "", true, true) != JSON.stringify(model.get(k, null), "", true, true):
			errs.append("difiere la seccion '%s'" % str(k))
	return errs


## Re-ejecuta `reproduce.config` y comprueba log_hash y contenido del informe. {"ok", "errors"}.
static func reproduce_individual(model: Dictionary, history: String = "") -> Dictionary:
	var rep: Dictionary = model.get("reproduce", {})
	if not rep.has("config"):
		return {"ok": false, "errors": ["el informe no guarda la configuracion para reproducirlo"]}
	var o := SimulationSession.open(rep["config"])
	if not bool(o["ok"]):
		return {"ok": false, "errors": o["errors"]}
	var s: SimulationSession = o["session"]
	var r := s.run_to_end()
	var errs: Array = []
	if r.log_hash != str(rep["log_hash"]):
		errs.append("log_hash distinto: %s != %s (otra version del motor o del contenido?)" % [r.log_hash.substr(0, 12), str(rep["log_hash"]).substr(0, 12)])
	var hist_mode: String = history if history != "" else str(model.get("history", {}).get("mode", "none"))
	var fresh: Dictionary = IndividualReport.build(s.engine, {"config": rep["config"], "history": hist_mode, "history_limit": int(model.get("history", {}).get("events", []).size()) if hist_mode == "summary" else 100000})["report"]
	var a: Dictionary = ReportExporter.canonical(model).duplicate()
	a.erase("balance")
	var b: Dictionary = fresh.duplicate()
	b.erase("balance")
	if ReportExporter.content_hash(a) != ReportExporter.content_hash(b):
		errs.append("el informe recalculado difiere del guardado")
	return {"ok": errs.is_empty(), "errors": errs}
