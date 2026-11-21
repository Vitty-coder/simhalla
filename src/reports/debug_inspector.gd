class_name DebugInspector
extends RefCounted
## Modo avanzado de DEPURACION (PROJECT.md §14.3): inspeccion completa del estado interno de un combate. Es un canal
## SEPARADO de la vista limitada de la IA (ViewBuilder): recibe el motor entero y nunca se entrega a una IA ni a un script
## (las pruebas comprueban que el codigo de `src/ai` y `src/scripting` no lo referencia y que la vista no filtra sus campos).
## Solo lectura: todo se devuelve como copias; no modifica el combate ni consume RNG.
##
## Contenido: estado interno de una entidad (estadisticas con desglose y modificadores con origen, recursos, estados, cooldowns y
## usos, canalizacion, variables de scripts, memoria de IA), estados del RNG, previsiones, eventos filtrados (por entidad, tipo,
## habilidad, cadena causal, rango), tiradas, explicacion de un evento con su cadena causal y modificaciones, causas de validacion
## de contenido y diagnostico de abortos.

var engine: CombatEngine


func _init(eng: CombatEngine) -> void:
	engine = eng


func entity_state(id: String) -> Dictionary:
	var e := engine.get_entity(id)
	if e == null:
		return {}
	var stats := {}
	for s in e.stats.stat_ids():
		var ex := e.stats.explain(s)
		ex["modifiers"] = e.stats.modifiers_for(s).map(func(m): return {"id": m.id, "kind": StatModifier.Kind.keys()[m.kind], "value": m.value, "source": m.source_id, "priority": m.priority, "seq": m.seq})
		stats[s] = ex
	var res := {}
	for rid in e.resources:
		var r: ResourceState = e.resources[rid]
		res[rid] = {"value": r.value, "min": r.min_value, "max": r.max_value if r.max_value != INF else null, "initial": r.initial, "regen_per_turn": r.regen_per_turn}
	var abilities := {}
	for a in e.abilities:
		abilities[a.id] = {"state": AbilityRuntime.state(e, a).duplicate(true), "blocked_reason": AbilityRuntime.blocked_reason(engine, e, a), "triggered": a.is_triggered()}
	return {
		"id": e.id, "team": e.team, "slot": e.slot, "alive": e.alive, "hp": e.hp, "hp_max": e.hp_max(), "initiative_micro": e.initiative_micro,
		"tags": e.tags.duplicate(), "stats": stats, "resources": res, "statuses": e.statuses.map(func(st): return st.to_dict()), "abilities": abilities,
		"channel": e.channel.duplicate(true), "script_vars": e.script_vars.duplicate(true), "ai": e.ai.ai_id() if e.ai != null else "none",
		"ai_memory": e.ai_memory.duplicate(true), "suspension_sources": e.suspension_sources.duplicate(true),
		"last_damage_source": e.last_damage_source, "owner_id": e.owner_id, "content_ref": e.content_ref.duplicate(true),
	}


func stat_breakdown(id: String, stat: String) -> Dictionary:
	var e := engine.get_entity(id)
	return e.stats.explain(stat) if e != null else {}


func rng_states() -> Dictionary:
	return engine.rng.get_states()


func scheduler_state() -> Dictionary:
	return {"now_micro": engine.scheduler.now, "threshold": engine.scheduler.threshold, "timed_pending": engine.scheduler.timed_count(),
		"next_timed_micro": engine.scheduler.next_timed_time(), "forecast": engine.scheduler.forecast(engine.entities, 8)}


## Filtros: {"entity": id (origen o destino), "type": tipo, "ability": id (por cadena causal), "chain_of": id de evento
## (el evento y TODOS sus ancestros), "descendants_of": id, "from": id, "to": id, "limit": n}. Requiere traza completa.
func filter_events(f: Dictionary) -> Array:
	var all: Array = engine.log.events
	var idx := {}
	for ev in all:
		idx[int(ev["id"])] = ev
	var allowed: Dictionary = {}
	if f.has("chain_of"):
		var cur: int = int(f["chain_of"])
		var guard := 0
		while idx.has(cur) and guard < 10000:
			guard += 1
			allowed[cur] = true
			cur = int(idx[cur]["cause"])
	var out: Array = []
	var limit := int(f.get("limit", 100000))
	for ev in all:
		var id := int(ev["id"])
		if f.has("from") and id < int(f["from"]):
			continue
		if f.has("to") and id > int(f["to"]):
			continue
		if f.has("entity") and str(ev["source"]) != str(f["entity"]) and str(ev["target"]) != str(f["entity"]):
			continue
		if f.has("type") and str(ev["type"]) != str(f["type"]):
			continue
		if f.has("chain_of") and not allowed.has(id):
			continue
		if f.has("descendants_of") and not _descends(idx, id, int(f["descendants_of"])):
			continue
		if f.has("ability") and IndividualReport._ability_of(ev, {"idx": idx}) != str(f["ability"]):
			continue
		out.append(ev.duplicate(true))
		if out.size() >= limit:
			break
	return out


static func _descends(idx: Dictionary, id: int, ancestor: int) -> bool:
	var cur: int = id
	var guard := 0
	while idx.has(cur) and guard < 10000:
		guard += 1
		if cur == ancestor:
			return true
		cur = int(idx[cur]["cause"])
	return false


## Tiradas del RNG de combate registradas (impacto, critico, proc): probabilidad, tirada y resultado.
func rolls(entity: String = "") -> Array:
	var out: Array = []
	for ev in engine.log.events:
		if ["hit", "miss", "crit", "proc"].has(str(ev["type"])) and ev["data"].has("roll") or (str(ev["type"]) == "crit" and ev["data"].has("chance")):
			if entity != "" and str(ev["source"]) != entity and str(ev["target"]) != entity:
				continue
			out.append({"id": ev["id"], "type": ev["type"], "source": ev["source"], "target": ev["target"], "chance": ev["data"].get("chance"), "roll": ev["data"].get("roll"),
				"success": ev["data"].get("success", ev["type"] == "hit" or ev["type"] == "crit"), "forced": ev["data"].get("forced", false)})
	return out


## Un evento con su cadena causal y las modificaciones que sufrio (event_modified/event_cancelled hijos).
func explain_event(id: int) -> Dictionary:
	var idx := {}
	for ev in engine.log.events:
		idx[int(ev["id"])] = ev
	if not idx.has(id):
		return {}
	var chain: Array = []
	var cur := id
	var guard := 0
	while idx.has(cur) and guard < 10000:
		guard += 1
		chain.append((idx[cur] as Dictionary).duplicate(true))
		cur = int(idx[cur]["cause"])
	var mods: Array = []
	for ev in engine.log.events:
		if (ev["type"] == "event_modified" or ev["type"] == "event_cancelled") and int(ev["data"].get("event", -1)) == id:
			mods.append(ev.duplicate(true))
	return {"event": idx[id].duplicate(true), "causal_chain": chain, "modifications": mods}


## Causas de validacion de un contenido: errores tecnicos (esquema, referencias, formulas, scripts), y valoracion de PC
## (presupuesto/no evaluable). `data` = diccionario de entidad. {"technical", "warnings", "balance"}.
static func validation_causes(data: Dictionary, profile: BalanceProfile, rules: Ruleset, balance_mode: String = "free", budget: String = "") -> Dictionary:
	var built := EntityFactory.build(data, profile, rules, OperationRegistry.new())
	var out := {"technical": built["errors"], "warnings": built["warnings"], "balance": {}}
	if profile.has_costs():
		out["balance"] = BalanceEvaluator.evaluate(data, profile, rules, OperationRegistry.new(), {"mode": balance_mode, "budget": budget}).to_dict()
	return out


## Diagnostico de un aborto tecnico: error, y los ultimos eventos antes de abortar.
func abort_diagnostic(last: int = 20) -> Dictionary:
	var e := engine.get_error()
	if e.is_empty():
		return {}
	var evs: Array = engine.log.events
	return {"error": e.duplicate(), "last_events": evs.slice(maxi(evs.size() - last, 0)).map(func(x): return x.duplicate(true))}
