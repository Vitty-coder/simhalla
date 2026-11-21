class_name BatchResult
extends RefCounted
## Resultado de un lote (completo, parcial o cancelado): registros por trabajo, resumen agregado, huella y rendimiento.
##
## `fingerprint` = SHA-256 de (version del motor, huella del plan, y por trabajo en ORDEN: indice, semilla, estado,
## log_hash). NO incluye tiempos ni el numero de workers: el mismo lote da la misma huella con 1 o N workers, en
## cualquier orden de ejecucion y con traza reducida o completa. `perf` es metadato de medicion (no reproducible).

var plan: Dictionary = {}
var plan_fingerprint: String = ""
var engine_version: String = ""
var records: Array = [] ## por indice de trabajo; null = no ejecutado (cancelado antes de empezar)
var summary: Dictionary = {}
var fingerprint: String = ""
var perf: Dictionary = {}
var status: String = "complete" ## complete | cancelled
var total_jobs: int = 0
var executed: int = 0
var contents: Dictionary = {} ## escenario -> [{id, version, hash, dependencies}] (de la primera ejecucion)


func is_complete() -> bool:
	return status == "complete"


func pending() -> int:
	return total_jobs - executed


static func compute_fingerprint(version: String, plan_fp: String, recs: Array) -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(("%s|%s\n" % [version, plan_fp]).to_utf8_buffer())
	for r in recs:
		if r != null:
			h.update(("%d|%d|%s|%s\n" % [int(r["index"]), int(r["seed"]), str(r["status"]), str(r.get("log_hash", ""))]).to_utf8_buffer())
	return h.finish().hex_encode()


func to_dict(include_records: bool = true) -> Dictionary:
	var d := {
		"plan": plan, "plan_fingerprint": plan_fingerprint, "engine_version": engine_version, "status": status,
		"total_jobs": total_jobs, "executed": executed, "pending": pending(), "fingerprint": fingerprint,
		"summary": summary, "contents": contents, "perf": perf,
	}
	if include_records:
		d["records"] = records.filter(func(r): return r != null)
	return d


## Version para persistir en JSON: las semillas de 64 bits van como TEXTO (un numero JSON perderia precision).
func to_storable() -> Dictionary:
	var d := to_dict(true)
	var p: Dictionary = (d["plan"] as Dictionary).duplicate(true)
	p["master_seed"] = str(p.get("master_seed", 1))
	d["plan"] = p
	d["records"] = (d["records"] as Array).map(func(r):
		var c: Dictionary = (r as Dictionary).duplicate(false)
		c["seed"] = str(c["seed"])
		return c)
	return d


## Reconstruye un resultado guardado (`to_dict(true)`): permite generar informes de lotes antiguos.
static func from_dict(d: Dictionary) -> BatchResult:
	var r := BatchResult.new()
	r.plan = (d.get("plan", {}) as Dictionary).duplicate(true)
	if r.plan.has("master_seed"):
		r.plan["master_seed"] = int(str(r.plan["master_seed"]))
	r.plan_fingerprint = str(d.get("plan_fingerprint", ""))
	r.engine_version = str(d.get("engine_version", ""))
	r.status = str(d.get("status", "complete"))
	r.total_jobs = int(d.get("total_jobs", 0))
	r.fingerprint = str(d.get("fingerprint", ""))
	r.summary = d.get("summary", {})
	r.contents = d.get("contents", {})
	r.perf = d.get("perf", {})
	r.records.resize(r.total_jobs)
	for rec in d.get("records", []):
		var c: Dictionary = (rec as Dictionary).duplicate(false)
		c["seed"] = int(str(c["seed"])) if c["seed"] is String else int(c["seed"])
		c["index"] = int(c["index"])
		r.records[int(c["index"])] = c
	r.executed = (d.get("records", []) as Array).size()
	return r
