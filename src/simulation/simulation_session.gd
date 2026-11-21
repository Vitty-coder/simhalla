class_name SimulationSession
extends RefCounted
## Simulacion INDIVIDUAL controlable, sin UI: la misma maquinaria que el combate normal y los lotes.
##
## Control: avanzar por acciones (`step_action`) o turnos (`step_turn`), `advance(n)` (la UI decide cuantos
## pasos por fotograma = velocidad), pausar/reanudar, resolver al instante (`run_to_end`) y cancelar.
## Inspeccion: `snapshot()` (estado de solo lectura), `forecast(n)` (orientativo: puede cambiar), lectura
## incremental del registro (`events_since`), cadena causal de un evento (`causal_chain`).
## Hacia atras: `reconstruct_at(paso)` reconstruye DETERMINISTAMENTE el estado de un paso anterior en una
## sesion nueva (misma configuracion y semilla, rejugada hasta ese paso); no modifica la partida real.
## "Paso" = un paso del motor (comenzar un turno, o resolver una decision/accion). La UI no ejecuta reglas.
## Las diferencias de la configuracion inicial (`initial_overrides`) quedan registradas en `combat_started`.

var config: Dictionary = {}
var engine: CombatEngine = null
var step_count: int = 0
var paused: bool = false
var errors: Array = []
var _cursor: int = 0


## Abre una sesion. La traza es siempre COMPLETA (se inspecciona). {"ok", "errors", "session"}.
static func open(cfg: Dictionary) -> Dictionary:
	var c: Dictionary = cfg.duplicate(true)
	c["trace"] = "full"
	var built := DuelRunner.build_engine(c)
	if not bool(built["ok"]):
		return {"ok": false, "errors": built["errors"], "session": null}
	var s := SimulationSession.new()
	s.config = c
	s.engine = built["engine"]
	return {"ok": true, "errors": [], "session": s}


func is_finished() -> bool:
	return engine.state == CombatEngine.State.ENDED


func result() -> CombatResult:
	return engine.result


# --- Control -----------------------------------------------------------------------------------------------

## Un paso del motor. Devuelve true mientras el combate siga en marcha. En pausa no avanza.
func step_action() -> bool:
	if paused or is_finished():
		return not is_finished()
	var more := engine.step()
	step_count += 1
	return more


## Avanza hasta completar el turno en curso (si no hay, hasta completar el siguiente) o hasta el final.
func step_turn() -> bool:
	if paused or is_finished():
		return not is_finished()
	var guard := 0
	while not is_finished() and guard < 100000:
		guard += 1
		step_action()
		if engine.turn == null:
			break
	return not is_finished()


## Hasta `n` pasos (la UI lo llama cada fotograma; la velocidad es `n`). Devuelve los realizados.
func advance(n: int) -> int:
	var done := 0
	while done < n and not paused and not is_finished():
		step_action()
		done += 1
	return done


func pause() -> void:
	paused = true


func resume() -> void:
	paused = false


## Resuelve instantaneamente hasta el final (ignora la pausa).
func run_to_end() -> CombatResult:
	paused = false
	while not is_finished():
		step_action()
	return engine.result


func cancel() -> void:
	engine.request_cancel()


# --- Inspeccion --------------------------------------------------------------------------------------------

## Estado de solo lectura (copias): tiempo, turno, entidades con vida/iniciativa/recursos/estados.
func snapshot() -> Dictionary:
	var scale := float(Ruleset.TIME_SCALE)
	var ents: Array = []
	for e in engine.entities:
		var res := {}
		for rid in e.resources:
			res[rid] = (e.resources[rid] as ResourceState).value
		ents.append({
			"id": e.id, "team": e.team, "alive": e.alive, "hp": e.hp, "hp_max": e.hp_max(),
			"initiative": float(e.initiative_micro) / scale, "resources": res,
			"statuses": e.statuses.map(func(st): return {"id": st.def.id, "stacks": st.stacks, "magnitude": st.magnitude}),
			"channeling": not e.channel.is_empty(),
		})
	return {
		"step": step_count, "time": float(engine.scheduler.now) / scale, "turn": engine.turn_count, "actions": engine.action_count,
		"current_entity": engine.turn.entity.id if engine.turn != null else "", "events": engine.log.count,
		"finished": is_finished(), "entities": ents,
	}


## Proximos turnos segun el estado ATB actual. SOLO orientativo: cambia si cambian las condiciones.
func forecast(count: int = 6) -> Array:
	return engine.scheduler.forecast(engine.entities, count)


## Eventos registrados desde la ultima lectura (lectura incremental para un visor).
func events_since_last() -> Array:
	var out: Array = []
	var all := engine.log.events
	for i in range(_cursor, all.size()):
		out.append(all[i])
	_cursor = all.size()
	return out


## Cadena causal (del evento hasta la raiz) para inspeccionar decisiones, formulas y tiradas.
func causal_chain(event_id: int) -> Array:
	var by_id := {}
	for ev in engine.log.events:
		by_id[int(ev["id"])] = ev
	var chain: Array = []
	var cur: int = event_id
	var guard := 0
	while by_id.has(cur) and guard < 10000:
		guard += 1
		chain.append(by_id[cur])
		cur = int(by_id[cur]["cause"])
	return chain


# --- Reconstruccion hacia atras ------------------------------------------------------------------------------

## Sesion NUEVA (misma configuracion y semilla) rejugada hasta `step` pasos: el estado exacto de ese
## instante. Es una inspeccion; no toca esta sesion. Determinista por construccion.
func reconstruct_at(step: int) -> SimulationSession:
	var o := SimulationSession.open(config)
	if not bool(o["ok"]):
		return null
	var s: SimulationSession = o["session"]
	s.advance(maxi(step, 0))
	return s


## Nueva sesion identica, para repetir con la misma semilla.
func repeat_same_seed() -> SimulationSession:
	return reconstruct_at(0)
