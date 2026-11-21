class_name AtbScheduler
extends RefCounted
## Reloj ATB de tiempo virtual y cola de eventos temporizados.
##
## - Tiempo e iniciativa son ENTEROS en microunidades (Ruleset.TIME_SCALE), lo
##   que hace exactas las comparaciones y los empates (determinismo).
## - Ganancia: delta_initiative = SPD * delta_time (SPD <= 0 no gana iniciativa).
## - El motor salta directamente al siguiente instante relevante (turno o
##   evento temporizado); no se simulan frames vacios.
## - Como las estadisticas solo cambian en eventos, y el reloj siempre se
##   adelanta hasta el instante del evento ANTES de procesarlo, la iniciativa
##   acumulada esta al dia antes de cualquier modificacion de SPD.

const NEVER := -1

var now: int = 0
var threshold: int = 0
var _timed: Array[Dictionary] = []
var _timed_seq: int = 0
var _rules: Ruleset


func _init(rules: Ruleset) -> void:
	_rules = rules
	threshold = rules.threshold_micro()


# --- Eventos temporizados -----------------------------------------------------

## Programa `fn(engine)` en el instante virtual `at_time` (microunidades).
func schedule(at_time: int, fn: Callable, label: String = "", data: Dictionary = {}) -> int:
	_timed_seq += 1
	_timed.append({"time": at_time, "seq": _timed_seq, "fn": fn, "label": label, "data": data})
	_timed.sort_custom(func(a, b): return a["time"] < b["time"] or (a["time"] == b["time"] and a["seq"] < b["seq"]))
	return _timed_seq


func cancel_timed(seq: int) -> bool:
	for i in _timed.size():
		if _timed[i]["seq"] == seq:
			_timed.remove_at(i)
			return true
	return false


## Descarta los eventos temporizados pendientes (rompe ciclos con closures).
func clear_timed() -> void:
	_timed.clear()


func next_timed_time() -> int:
	return _timed[0]["time"] if not _timed.is_empty() else NEVER


func timed_count() -> int:
	return _timed.size()


## Extrae el siguiente evento temporizado si vence en `at_time` o antes.
func pop_timed_due(at_time: int) -> Dictionary:
	if not _timed.is_empty() and _timed[0]["time"] <= at_time:
		return _timed.pop_front()
	return {}


# --- Iniciativa -----------------------------------------------------------------

func spd_of(e: CombatEntity) -> float:
	return maxf(e.stats.get_value("SPD"), 0.0) # politica clamp_zero


func can_gain(e: CombatEntity) -> bool:
	return e.alive and not e.is_suspended() and spd_of(e) > 0.0


func is_ready(e: CombatEntity) -> bool:
	return e.alive and not e.is_suspended() and e.initiative_micro >= threshold


## Microunidades de tiempo hasta que `e` alcanza el umbral; NEVER si no puede.
func time_until_ready(e: CombatEntity) -> int:
	if not e.alive or e.is_suspended():
		return NEVER
	if e.initiative_micro >= threshold:
		return 0
	if not can_gain(e):
		return NEVER
	var remaining: float = float(threshold - e.initiative_micro)
	return int(ceil(remaining / spd_of(e)))


## Adelanta la iniciativa de todos `dt` microunidades de tiempo.
func advance(entities: Array, dt: int) -> void:
	if dt <= 0:
		return
	for e in entities:
		var ent: CombatEntity = e
		if not can_gain(ent):
			continue
		ent.initiative_micro += int(round(spd_of(ent) * float(dt)))
	now += dt


## Instante del proximo turno (>= now) o NEVER.
func next_turn_time(entities: Array) -> int:
	var best := NEVER
	for e in entities:
		var dt := time_until_ready(e)
		if dt == NEVER:
			continue
		if best == NEVER or dt < best:
			best = dt
	return NEVER if best == NEVER else now + best


## Planifica el siguiente paso: {"kind": "turn"|"timed"|"none", "time": int}.
func plan(entities: Array) -> Dictionary:
	var t_turn := next_turn_time(entities)
	var t_timed := next_timed_time()
	if t_turn == NEVER and t_timed == NEVER:
		return {"kind": "none", "time": now}
	if t_turn == NEVER:
		return {"kind": "timed", "time": maxi(t_timed, now)}
	if t_timed == NEVER:
		return {"kind": "turn", "time": t_turn}
	var timed_first: bool = bool(_rules.get_path_value("atb.timed_events_first"))
	if t_timed < t_turn or (t_timed == t_turn and timed_first):
		return {"kind": "timed", "time": maxi(t_timed, now)}
	return {"kind": "turn", "time": t_turn}


## Entidades listas, ordenadas segun los criterios de desempate configurados.
func ready_entities(entities: Array, tie_rng: Rng) -> Array:
	var ready: Array = []
	for e in entities:
		if is_ready(e):
			ready.append(e)
	if ready.size() <= 1:
		return ready
	var criteria: Array = _rules.tie_break()
	var use_random := criteria.has("random")
	# Clave aleatoria reproducible solo si el criterio la usa.
	var rand_key := {}
	if use_random:
		for e in ready:
			rand_key[e.id] = tie_rng.next_u64() if tie_rng != null else 0
	ready.sort_custom(func(a: CombatEntity, b: CombatEntity) -> bool:
		for c in criteria:
			match c:
				"initiative_excess_desc":
					if a.initiative_micro != b.initiative_micro:
						return a.initiative_micro > b.initiative_micro
				"spd_desc":
					var sa := spd_of(a)
					var sb := spd_of(b)
					if sa != sb:
						return sa > sb
				"slot_asc":
					if a.slot != b.slot:
						return a.slot < b.slot
				"random":
					if rand_key[a.id] != rand_key[b.id]:
						return rand_key[a.id] < rand_key[b.id]
		return a.slot < b.slot) # orden total final: nunca depende del algoritmo de sort
	return ready


## Previsiones de proximos turnos (solo orientativo; puede cambiar).
func forecast(entities: Array, count: int) -> Array:
	var sim: Array = []
	for e in entities:
		if e.alive:
			sim.append({"id": e.id, "init": e.initiative_micro, "spd": spd_of(e), "slot": e.slot, "can": can_gain(e)})
	var out: Array = []
	var t := now
	var guard := 0
	while out.size() < count and guard < count * 8:
		guard += 1
		var best_dt := NEVER
		for s in sim:
			var dt: int
			if s["init"] >= threshold:
				dt = 0
			elif not s["can"]:
				continue
			else:
				dt = int(ceil(float(threshold - s["init"]) / float(s["spd"])))
			if best_dt == NEVER or dt < best_dt:
				best_dt = dt
		if best_dt == NEVER:
			break
		for s in sim:
			if s["can"]:
				s["init"] += int(round(float(s["spd"]) * float(best_dt)))
		t += best_dt
		var ready: Array = sim.filter(func(s): return s["init"] >= threshold)
		ready.sort_custom(func(a, b): return a["init"] > b["init"] or (a["init"] == b["init"] and a["slot"] < b["slot"]))
		if ready.is_empty():
			break
		var pick: Dictionary = ready[0]
		pick["init"] -= threshold
		out.append({"id": pick["id"], "time": float(t) / float(Ruleset.TIME_SCALE)})
	return out
