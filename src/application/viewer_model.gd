class_name ViewerModel
extends RefCounted
## Modelo del VISOR de batalla (sin nodos): reproduce un combate (nuevo o guardado) con los controles de PROJECT.md §12.3:
## pausar/reanudar, avanzar por acciones o turnos, velocidad, resolver al instante, RETROCEDER (reconstruccion determinista:
## inspeccion, nunca modifica la partida real), repetir con la misma semilla e inspeccionar un evento (decisiones, formulas,
## tiradas, modificadores). La UI no ejecuta reglas: solo llama a estos metodos y presenta `view()`.

const MAX_SPEED := 64

var app: AppController
var config: Dictionary
var session: SimulationSession
var refs: Array = []
var source_battle_id: String = ""
var matches_saved: bool = true
var warnings: Array = []
var speed: int = 1
var playing: bool = false
var selected_event: int = -1
var _final: SimulationSession = null


## Abre un visor sobre una configuracion (idealmente fijada). {"ok","viewer","errors"}.
static func open(a: AppController, cfg: Dictionary, opts: Dictionary = {}) -> Dictionary:
	var o := SimulationSession.open(cfg)
	if not bool(o["ok"]):
		return {"ok": false, "viewer": null, "errors": o["errors"]}
	var v := ViewerModel.new()
	v.app = a
	v.config = cfg
	v.session = o["session"]
	v.refs = opts.get("refs", [])
	return {"ok": true, "viewer": v, "errors": []}


## Reproduce un combate guardado con su configuracion fijada (avisa si el resultado no coincide o cambio el motor).
static func from_battle(a: AppController, id: String) -> Dictionary:
	var rp := a.storage.replay_battle(id)
	if not bool(rp["ok"]):
		return {"ok": false, "viewer": null, "errors": rp["errors"], "warnings": rp["warnings"]}
	var v := ViewerModel.new()
	v.app = a
	v.session = rp["session"]
	v.config = (a.storage.load_battle(id)["record"]["config"] as Dictionary).duplicate(true)
	v.config["library"] = a.storage.library.root
	v.source_battle_id = id
	v.matches_saved = bool(rp["matches"])
	v.warnings = rp["warnings"]
	return {"ok": true, "viewer": v, "errors": [], "warnings": rp["warnings"]}


# --- Control ---------------------------------------------------------------------------------------------------------------

func play() -> void:
	playing = true


func pause() -> void:
	playing = false


func toggle() -> void:
	playing = not playing


func set_speed(n: int) -> void:
	speed = clampi(n, 1, MAX_SPEED)


## La UI lo llama una vez por fotograma (o por temporizador): avanza `speed` pasos si esta reproduciendo.
func tick() -> int:
	if not playing or session.is_finished():
		if session.is_finished():
			playing = false
		return 0
	var n := session.advance(speed)
	if session.is_finished():
		playing = false
	return n


func step_action() -> bool:
	playing = false
	return session.step_action()


func step_turn() -> bool:
	playing = false
	return session.step_turn()


func to_end() -> void:
	playing = false
	session.run_to_end()


## Pasos totales del combate (se calcula una vez rejugandolo hasta el final en una sesion aparte).
func total_steps() -> int:
	return _final_session().step_count


func _final_session() -> SimulationSession:
	if _final == null:
		_final = session.repeat_same_seed()
		_final.run_to_end()
	return _final


## Salta a un paso (hacia atras reconstruye de forma determinista; hacia delante avanza).
func seek(step: int) -> void:
	playing = false
	var target := clampi(step, 0, total_steps())
	if target < session.step_count:
		session = session.reconstruct_at(target)
	elif target > session.step_count:
		session.advance(target - session.step_count)


func rewind(n: int = 1) -> void:
	seek(session.step_count - n)


func forward(n: int = 1) -> void:
	seek(session.step_count + n)


func restart() -> void:
	seek(0)


## Nueva sesion identica (misma semilla) como sesion actual.
func repeat_same_seed() -> void:
	session = session.repeat_same_seed()
	playing = false
	selected_event = -1


# --- Presentacion ------------------------------------------------------------------------------------------------------------------

func position() -> Dictionary:
	var total := total_steps()
	return {"step": session.step_count, "total": total, "percent": float(session.step_count) / float(maxi(total, 1)), "finished": session.is_finished(), "playing": playing, "speed": speed}


## Lineas legibles del registro (solo eventos visibles). [{id, text, type, source, target, t}]
func log_lines(limit: int = 60) -> Array:
	var out: Array = []
	var evs: Array = session.engine.log.events
	var i := evs.size() - 1
	while i >= 0 and out.size() < limit:
		var ev: Dictionary = evs[i]
		if EventText.is_visible(str(ev["type"])):
			out.append({"id": ev["id"], "text": EventText.describe(ev), "type": ev["type"], "source": ev["source"], "target": ev["target"], "t": float(ev["time"]) / float(Ruleset.TIME_SCALE)})
		i -= 1
	out.reverse()
	return out


## Todo lo que pinta la pantalla en un instante.
func view(log_limit: int = 40) -> Dictionary:
	var snap := session.snapshot()
	var names := {}
	for spec in config.get("entities", []):
		var id := str((spec.get("overrides", {}) as Dictionary).get("id", ""))
		names[id] = str(spec.get("package", spec.get("source_path", spec.get("path", id)))).get_file()
	for e in snap["entities"]:
		e["display_name"] = names.get(e["id"], e["id"])
	return {"snapshot": snap, "forecast": session.forecast(6), "position": position(), "log": log_lines(log_limit), "selected": inspect(), "warnings": warnings,
		"matches_saved": matches_saved, "result": _result_summary()}


func _result_summary() -> Dictionary:
	if not session.is_finished():
		return {}
	var r := session.result()
	return {"outcome": r.outcome, "winner_team": r.winner_team, "reason": r.reason, "kind": r.kind, "turns": r.turns, "log_hash": r.log_hash}


func select_event(id: int) -> void:
	selected_event = id


## Inspeccion de un evento: cadena causal, modificaciones, y el detalle de formulas/tiradas de sus datos.
func inspect() -> Dictionary:
	if selected_event < 0:
		return {}
	var ex := DebugInspector.new(session.engine).explain_event(selected_event)
	if ex.is_empty():
		return {}
	var ev: Dictionary = ex["event"]
	var d: Dictionary = ev["data"]
	var detail: Array = []
	for k in ["chance", "roll", "base", "premitigation", "defense_used", "resistance_used", "intended", "mitigated", "amount", "applied", "overkill", "raw", "overheal", "crit"]:
		if d.has(k):
			detail.append([k, d[k]])
	return {"event": ev, "text": EventText.describe(ev), "detail": detail, "causal_chain": ex["causal_chain"].map(func(e): return {"id": e["id"], "type": e["type"], "text": EventText.describe(e)}),
		"modifications": ex["modifications"]}


func debug() -> DebugInspector:
	return DebugInspector.new(session.engine)


# --- Guardar / informar ---------------------------------------------------------------------------------------------------------------

## Guarda el combate COMPLETO (se rejuega hasta el final en una sesion aparte; la actual no se toca). {"ok","id","error"}.
func save(title: String = "", with_trace: bool = false) -> Dictionary:
	var fin := _final_session()
	return app.storage.save_battle(fin, config, {"title": title if title != "" else "Combate %s" % fin.result().log_hash.substr(0, 8), "with_trace": with_trace})


## Informe individual del combate completo (modelo). Se guarda con `save_report`.
func report(history: String = "") -> Dictionary:
	var h := history if history != "" else str(app.settings()["history"])
	var r := IndividualReport.build(_final_session().engine, {"config": config, "history": h})
	return r


func save_report(battle_id: String = "", title: String = "") -> Dictionary:
	var r := report()
	if not bool(r["ok"]):
		return {"ok": false, "id": "", "error": "; ".join(r["errors"])}
	var rf: Array = []
	if battle_id != "":
		rf.append({"kind": "battle", "id": battle_id})
	return app.storage.save_report(r["report"], title if title != "" else "Informe %s" % _final_session().result().log_hash.substr(0, 8), rf)
