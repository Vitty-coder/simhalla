class_name BatchRunner
extends RefCounted
## Ejecuta un BatchPlan con el MISMO motor que el combate individual, sin escenas ni nodos por duelo.
##
## Modos de ejecucion:
##   workers = 0  sincrono cooperativo: `run_slice(max_jobs, max_ms)` ejecuta una porcion y devuelve el control
##                (la UI/Android lo llama por fotograma); `wait()` termina todo.
##   workers >= 1 hilos de segundo plano (limitados a MAX_WORKERS): `start()`, `poll()` (desde el hilo principal:
##                agrega incrementalmente y devuelve el progreso), `wait()`.
## Aislamiento: cada trabajo construye su propio reglamento/perfil/registro/motor (nada mutable compartido), asi que el
## resultado NO depende del orden de ejecucion ni de los workers. `cancel()` detiene lo no empezado y pide a los
## combates en curso que aborten (quedan como `cancelled`, NUNCA como derrota/empate); los terminados son validos y
## reproducibles. Cada registro permite reproducir su duelo (`replay`) con traza completa.
##
## options: {"workers": 0, "keep_traces": false (guarda el registro de eventos de TODOS los trabajos: mucha memoria),
##           "on_progress": Callable(progress: Dictionary) (hilo principal, desde poll/run_slice)}

const MAX_WORKERS := 8

var plan: BatchPlan
var options: Dictionary = {}
var workers: int = 0
var keep_traces: bool = false
var results: Array = []
var accumulator: BatchAccumulator = BatchAccumulator.new()
var contents: Dictionary = {}

var _mutex: Mutex = Mutex.new()
var _next: int = 0
var _executed: int = 0
var _cancel: bool = false
var _queue: Array = [] ## indices terminados pendientes de agregar (hilo principal)
var _threads: Array = []
var _active: Dictionary = {} ## worker -> CombatEngine en curso
var _started_ms: int = 0
var _finished_ms: int = 0
var _started: bool = false
var _live_workers: int = 0


func _init(p: BatchPlan, opts: Dictionary = {}) -> void:
	plan = p
	options = opts
	workers = clampi(int(opts.get("workers", 0)), 0, MAX_WORKERS)
	keep_traces = bool(opts.get("keep_traces", false))
	results.resize(plan.job_count())


# --- Control -----------------------------------------------------------------------------------------------

func start() -> void:
	if _started:
		return
	_started = true
	_started_ms = Time.get_ticks_msec()
	if workers <= 0 or plan.job_count() == 0:
		return
	SemVer.compare("1.0.0", "1.0.0") # inicializa estaticos perezosos antes de lanzar hilos
	_prime()
	var n := mini(workers, plan.job_count())
	_live_workers = n
	for w in n:
		var t := Thread.new()
		_threads.append(t)
		t.start(_work.bind(w))


## Un combate descartable de UN turno del primer escenario: carga las clases/scripts que usara el lote antes de
## lanzar hilos (evita la primera carga concurrente) sin bloquear con un trabajo completo.
func _prime() -> void:
	var cfg := plan.job_config(0, "reduced")
	cfg["ruleset_overrides"] = Ruleset._merge(cfg.get("ruleset_overrides", {}), {"victory": {"limits": {"max_turns": 1, "max_actions": 5}}})
	var built := DuelRunner.build_engine(cfg)
	if bool(built["ok"]):
		(built["engine"] as CombatEngine).run()


func cancel() -> void:
	_mutex.lock()
	_cancel = true
	for w in _active:
		(_active[w] as CombatEngine).request_cancel()
	_mutex.unlock()


func is_cancelled() -> bool:
	return _cancel


## ¿Terminado (todos ejecutados, o cancelado y sin workers vivos)?
func is_finished() -> bool:
	_mutex.lock()
	var done := _executed >= plan.job_count() or (_cancel and _live_workers == 0 and _threads.size() > 0) or (_cancel and _threads.is_empty())
	_mutex.unlock()
	return done


func progress() -> Dictionary:
	_mutex.lock()
	var d := {"total": plan.job_count(), "done": _executed, "pending": plan.job_count() - _executed, "cancelled": _cancel,
		"workers": workers, "errors": int(accumulator.totals["aborted"]) + int(accumulator.totals["setup_errors"])}
	_mutex.unlock()
	return d


## Hilo principal: agrega lo terminado (incremental) y avisa. Devuelve el progreso.
func poll() -> Dictionary:
	_mutex.lock()
	var ready: Array = _queue.duplicate()
	_queue.clear()
	_mutex.unlock()
	for i in ready:
		accumulator.add(results[i])
	var p := progress()
	if options.get("on_progress", null) is Callable and (options["on_progress"] as Callable).is_valid():
		(options["on_progress"] as Callable).call(p)
	return p


## Modo cooperativo (workers = 0): ejecuta hasta `max_jobs` trabajos o `max_ms` ms y devuelve el progreso.
func run_slice(max_jobs: int = 1, max_ms: int = 0) -> Dictionary:
	start()
	var t0 := Time.get_ticks_msec()
	var done := 0
	while done < max_jobs and not _cancel and _next < plan.job_count():
		var i := _next
		_next += 1
		_store(i, _execute(i, 0))
		done += 1
		if max_ms > 0 and Time.get_ticks_msec() - t0 >= max_ms:
			break
	return poll()


## Bloquea hasta terminar (o cancelar) y devuelve el resultado.
func wait() -> BatchResult:
	start()
	if workers <= 0:
		while not _cancel and _next < plan.job_count():
			run_slice(16)
	else:
		while not is_finished():
			poll()
			OS.delay_msec(1)
		for t in _threads:
			(t as Thread).wait_to_finish()
		_threads.clear()
	poll()
	_finished_ms = Time.get_ticks_msec()
	return result()


## Resultado actual (parcial si no ha terminado o se cancelo). El resumen se recalcula en orden de trabajo.
func result() -> BatchResult:
	var r := BatchResult.new()
	r.plan = plan.to_dict()
	r.plan_fingerprint = plan.fingerprint()
	r.engine_version = CombatEngine.ENGINE_VERSION
	r.records = results.duplicate()
	r.total_jobs = plan.job_count()
	r.executed = 0
	for x in results:
		if x != null:
			r.executed += 1
	r.status = "complete" if r.executed == r.total_jobs else "cancelled"
	r.summary = BatchAccumulator.rebuild(results).summary()
	r.fingerprint = BatchResult.compute_fingerprint(r.engine_version, r.plan_fingerprint, results)
	r.contents = contents.duplicate(true)
	var end_ms := _finished_ms if _finished_ms > 0 else Time.get_ticks_msec()
	var wall := maxi(end_ms - _started_ms, 1)
	var events := 0
	for x in results:
		if x != null:
			events += int(x.get("events", 0))
	r.perf = {"wall_ms": wall, "jobs_per_s": float(r.executed) * 1000.0 / float(wall), "events_per_s": float(events) * 1000.0 / float(wall), "workers": workers}
	return r


# --- Trabajos ----------------------------------------------------------------------------------------------

func _work(worker: int) -> void:
	while true:
		_mutex.lock()
		if _cancel or _next >= plan.job_count():
			_live_workers -= 1
			_mutex.unlock()
			return
		var i := _next
		_next += 1
		_mutex.unlock()
		_store(i, _execute(i, worker))


func _store(i: int, rec: Dictionary) -> void:
	_mutex.lock()
	results[i] = rec
	_executed += 1
	_queue.append(i)
	_mutex.unlock()


func _record_base(i: int) -> Dictionary:
	var j: Dictionary = plan.jobs[i]
	var s: Dictionary = plan.scenarios[int(j["scenario"])]
	return {"index": i, "scenario": str(s["key"]), "scenario_label": str(s.get("label", s["key"])), "sides": s.get("sides", {}),
		"repetition": int(j["repetition"]), "seed": int(j["seed"]), "params": s.get("params", {})}


func _execute(i: int, worker: int) -> Dictionary:
	var rec := _record_base(i)
	var cfg := plan.job_config(i, "full" if keep_traces else "reduced")
	var built := DuelRunner.build_engine(cfg)
	if not bool(built["ok"]):
		rec["status"] = "setup_error"
		rec["error"] = "; ".join(built["errors"].map(func(e): return str(e)))
		return rec
	var eng: CombatEngine = built["engine"]
	_mutex.lock()
	_active[worker] = eng
	var cancelled_now := _cancel
	_mutex.unlock()
	if cancelled_now:
		eng.request_cancel()
	var res := eng.run()
	_mutex.lock()
	_active.erase(worker)
	_mutex.unlock()
	rec["reason"] = res.reason
	rec["kind"] = res.kind
	rec["turns"] = res.turns
	rec["actions"] = res.actions
	rec["events"] = res.events
	rec["end_time"] = res.end_time
	rec["log_hash"] = res.log_hash
	rec["winner_team"] = res.winner_team
	rec["metrics"] = res.metrics
	if res.is_aborted():
		rec["status"] = "cancelled" if res.kind == "cancelled" else "aborted"
		rec["error"] = "%s: %s" % [str(res.error.get("code", "")), str(res.error.get("message", ""))]
	else:
		rec["status"] = "win" if res.is_win() else "draw"
	rec["entities"] = res.entities
	rec["sides_stats"] = _sides_stats(res)
	rec["sides_abilities"] = _sides_abilities(res)
	if int(rec["repetition"]) == 0 and not contents.has(rec["scenario"]):
		_mutex.lock()
		contents[rec["scenario"]] = eng.entities.map(func(e): return {"id": e.id, "content": e.content_ref})
		_mutex.unlock()
	if keep_traces:
		rec["events_log"] = eng.log.events.duplicate()
	return rec


static func _sides_stats(res: CombatResult) -> Dictionary:
	var out := {}
	for id in res.entities:
		var team := str(res.entities[id]["team"])
		if not out.has(team):
			out[team] = {"damage_dealt": 0.0, "healing_done": 0.0, "hp_left": 0.0, "alive": 0}
		var st: Dictionary = res.stats.get(id, {})
		out[team]["damage_dealt"] += float(st.get("damage_dealt", 0.0))
		out[team]["healing_done"] += float(st.get("healing_done", 0.0))
		out[team]["hp_left"] += float(res.entities[id]["hp"])
		out[team]["alive"] += 1 if bool(res.entities[id]["alive"]) else 0
	return out


## Uso, dano y curacion efectivos por habilidad, sumados por equipo.
static func _sides_abilities(res: CombatResult) -> Dictionary:
	var out := {}
	for id in res.entities:
		var team := str(res.entities[id]["team"])
		if not out.has(team):
			out[team] = {}
		var abs: Dictionary = res.stats.get(id, {}).get("abilities", {})
		for a in abs:
			if not out[team].has(a):
				out[team][a] = {"uses": 0, "damage": 0.0, "healing": 0.0}
			out[team][a]["uses"] += int(abs[a]["uses"])
			out[team][a]["damage"] += float(abs[a]["damage_dealt"])
			out[team][a]["healing"] += float(abs[a]["healing_done"])
	return out


# --- Reproduccion ------------------------------------------------------------------------------------------

## Reproduce el trabajo `index` con traza completa (mismo motor, configuracion y semilla). {"ok","result","engine","config"}.
static func replay(p: BatchPlan, index: int, trace: String = "full") -> Dictionary:
	var cfg := p.job_config(index, trace)
	var out := DuelRunner.run(cfg)
	out["config"] = cfg
	return out


## ¿El registro se reproduce exactamente (mismo log_hash)?
static func verify(p: BatchPlan, rec: Dictionary) -> bool:
	var out := replay(p, int(rec["index"]), "reduced")
	return bool(out["ok"]) and (out["result"] as CombatResult).log_hash == str(rec.get("log_hash", ""))
