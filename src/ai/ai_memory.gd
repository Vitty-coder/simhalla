class_name AIMemory
extends RefCounted
## Memoria de combate de la IA (por entidad, nunca compartida entre batallas).
##
## Vive en `entity.ai_memory` y llega a la IA copiada dentro de la vista. Solo se
## alimenta de acontecimientos OBSERVABLES por esa entidad:
##   - su propio dano causado/recibido y sus tiradas de impacto,
##   - acciones publicas de los demas (habilidad usada, reacciones, inicio de turno).
## Nunca se leen estadisticas, cooldowns ni variables internas de otros.
##
## Estructura:
##   vars    {nombre: numero|bool|texto}  variables de la estrategia (via memory_ops)
##   obs     {id_entidad: observaciones}  ver `_obs`
##   history [ {turn, time, ability, targets} ]  ultimas acciones propias (max HISTORY_MAX)
##   state, state_since, own_turns        estado de la maquina de estados
##   last_hit_by                          ultimo rival que me dano
## La IA no escribe aqui: propone `memory_ops` en su decision y el motor las aplica.

const HISTORY_MAX := 16
const VARS_MAX := 32
const OBS_TYPES := [
	EventTypes.DAMAGE_DEALT, EventTypes.HIT, EventTypes.MISS, EventTypes.ACTION_RESOLVED,
	EventTypes.REACTION_TRIGGERED, EventTypes.TURN_STARTED, EventTypes.ACTION_SELECTED,
]


static func fresh() -> Dictionary:
	return {"vars": {}, "obs": {}, "history": [], "state": "", "state_since": 0, "own_turns": 0, "last_hit_by": ""}


## Registra los observadores solo cuando alguna IA los necesita (una vez por combate):
## evita coste en combates cuyas IAs no usan memoria ni prediccion.
static func ensure(engine: CombatEngine, ai: AIController) -> void:
	if ai != null and not engine.ai_memory_attached and ai.wants_memory():
		engine.ai_memory_attached = true
		attach(engine)


static func attach(engine: CombatEngine) -> void:
	for t in OBS_TYPES:
		engine.dispatcher.observe(t, func(ev: CombatEvent, g: CombatEngine): _on_event(g, ev), 100, "ai_memory")


static func _on_event(engine: CombatEngine, ev: CombatEvent) -> void:
	for ent in engine.entities:
		var e: CombatEntity = ent
		if not e.alive or e.ai == null or not e.ai.wants_memory():
			continue
		_observe(engine, e, ev)


static func _obs(mem: Dictionary, other_id: String) -> Dictionary:
	var all: Dictionary = mem["obs"]
	if not all.has(other_id):
		all[other_id] = {
			"dealt_total": 0.0, "dealt_n": 0, "taken_total": 0.0, "taken_n": 0,
			"swings": 0, "hits": 0, "mit": {}, "abilities_seen": {}, "reactions_seen": {},
			"last_ability": "", "turns_seen": 0, "last_turn_time": -1.0, "interval": 0.0,
		}
	return all[other_id]


static func _observe(engine: CombatEngine, e: CombatEntity, ev: CombatEvent) -> void:
	var mem: Dictionary = e.ai_memory
	var me := e.id
	match ev.type:
		EventTypes.DAMAGE_DEALT:
			if ev.source_id == me and ev.target_id != me and ev.target_id != "":
				var o := _obs(mem, ev.target_id)
				o["dealt_total"] = float(o["dealt_total"]) + float(ev.data.get("amount", 0.0))
				o["dealt_n"] = int(o["dealt_n"]) + 1
				var key := "%s|%s" % [str(ev.data.get("damage_type", "")), str(ev.data.get("element", ""))]
				var m: Dictionary = o["mit"]
				if not m.has(key):
					m[key] = {"pre": 0.0, "amt": 0.0}
				m[key]["pre"] = float(m[key]["pre"]) + float(ev.data.get("premitigation", 0.0))
				m[key]["amt"] = float(m[key]["amt"]) + float(ev.data.get("amount", 0.0))
			elif ev.target_id == me and ev.source_id != me and ev.source_id != "":
				var o2 := _obs(mem, ev.source_id)
				o2["taken_total"] = float(o2["taken_total"]) + float(ev.data.get("amount", 0.0))
				o2["taken_n"] = int(o2["taken_n"]) + 1
				mem["last_hit_by"] = ev.source_id
		EventTypes.HIT, EventTypes.MISS:
			if ev.source_id == me and ev.target_id != me and ev.target_id != "":
				var o3 := _obs(mem, ev.target_id)
				o3["swings"] = int(o3["swings"]) + 1
				if ev.type == EventTypes.HIT:
					o3["hits"] = int(o3["hits"]) + 1
		EventTypes.ACTION_RESOLVED:
			if ev.source_id != me and ev.source_id != "":
				var o4 := _obs(mem, ev.source_id)
				var ab := str(ev.data.get("ability", ""))
				var seen: Dictionary = o4["abilities_seen"]
				seen[ab] = int(seen.get(ab, 0)) + 1
				o4["last_ability"] = ab
		EventTypes.REACTION_TRIGGERED:
			if ev.source_id != me and ev.source_id != "":
				var o5 := _obs(mem, ev.source_id)
				var rs: Dictionary = o5["reactions_seen"]
				var ra := str(ev.data.get("ability", ""))
				rs[ra] = int(rs.get(ra, 0)) + 1
		EventTypes.TURN_STARTED:
			var now := float(engine.scheduler.now) / float(Ruleset.TIME_SCALE)
			if ev.source_id == me:
				mem["own_turns"] = int(mem["own_turns"]) + 1
			elif ev.source_id != "":
				var o6 := _obs(mem, ev.source_id)
				if float(o6["last_turn_time"]) >= 0.0:
					o6["interval"] = now - float(o6["last_turn_time"])
				o6["last_turn_time"] = now
				o6["turns_seen"] = int(o6["turns_seen"]) + 1
		EventTypes.ACTION_SELECTED:
			if ev.source_id == me and str(ev.data.get("kind", "")) == "ability":
				var h: Array = mem["history"]
				h.append({"turn": engine.turn_count, "time": float(engine.scheduler.now) / float(Ruleset.TIME_SCALE),
					"ability": str(ev.data.get("ability", "")), "targets": (ev.data.get("targets", []) as Array).duplicate()})
				if h.size() > HISTORY_MAX:
					h.pop_front()


## Aplica las operaciones de memoria propuestas por la IA (validadas aqui).
## op: set {key,value} | incr {key,value} | state {value}. Devuelve las aplicadas.
static func apply_ops(e: CombatEntity, ops: Array) -> Array:
	var applied: Array = []
	var mem: Dictionary = e.ai_memory
	for op in ops:
		if not (op is Dictionary):
			continue
		match str(op.get("op", "")):
			"set", "incr":
				var key := str(op.get("key", ""))
				var val: Variant = op.get("value", 0)
				if key == "" or not (val is float or val is int or val is bool or val is String):
					continue
				var vars: Dictionary = mem["vars"]
				if not vars.has(key) and vars.size() >= VARS_MAX:
					continue
				if str(op["op"]) == "incr":
					if not (val is float or val is int):
						continue
					vars[key] = float(vars.get(key, 0.0)) + float(val)
				else:
					vars[key] = val
				applied.append(op)
			"state":
				mem["state"] = str(op.get("value", ""))
				mem["state_since"] = int(mem["own_turns"])
				applied.append(op)
	return applied
