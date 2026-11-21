class_name CombatEngine
extends RefCounted
## Motor de combate ATB headless. Sin dependencias de UI, Nodes, framerate ni
## reloj de pared: todo el tiempo es virtual y todo el azar sale de RngService.
##
## Uso:
##   var eng := CombatEngine.new()
##   var errs := eng.setup(ruleset, [a, b], seed)      # [] si es valido
##   var result := eng.run()                           # o step() accion a accion
##
## step() avanza UNA unidad de progreso: buscar el siguiente turno (adelantando
## el reloj y disparando eventos temporizados) o resolver una decision de la IA.
## Las simulaciones masivas y el visor usan este mismo motor.

const ENGINE_VERSION := "0.5.0"

enum State { NEW, RUNNING, ENDED }

var rules: Ruleset
var rng: RngService
var entities: Array[CombatEntity] = []
var scheduler: AtbScheduler
var dispatcher: EventDispatcher = EventDispatcher.new()
var log: EventLog
var registry: OperationRegistry = OperationRegistry.new()
var catalog: StatusCatalog = StatusCatalog.new()
var status_service: StatusService = null
var defense_service: DefenseService = null
var trigger_service: TriggerService = null
var profile: BalanceProfile = null ## perfil con el que se construyen las invocaciones
var reaction_depth: int = 0
var ai_memory_attached: bool = false
var free_depth: int = 0
var summon_counter: int = 0
var scheduled_count: int = 0
var custom_metrics: Dictionary = {} ## nombre -> {"total", "count", "by_entity"}
var stats: CombatStats = CombatStats.new()
var current_action_started_id: int = 0
var end_conditions: Array[VictoryCondition] = []

var state: State = State.NEW
var turn: TurnState = null
var turn_count: int = 0
var action_count: int = 0
var last_hp_change_turn: int = 0
var result: CombatResult = null
var seed_value: int = 0

var _by_id: Dictionary = {}
var _event_seq: int = 0
var _depth: int = 0
var _aborted: bool = false
var _error: Dictionary = {}
var _cancel_requested: bool = false
var _formulas: Dictionary = {}
var _overrides_applied: Dictionary = {}


# --- Preparacion ------------------------------------------------------------------

## Devuelve la lista de errores de configuracion ([] si todo es valido).
## `overrides`: {entity_id: {"hp": x, "initiative": x, "resources": {id: valor}}}
func setup(rules_: Ruleset, entities_: Array, seed_: int, trace: EventLog.TraceLevel = EventLog.TraceLevel.FULL, overrides: Dictionary = {}) -> Array:
	var errs: Array = []
	if rules_ == null:
		return ["reglamento ausente"]
	if not rules_.is_valid():
		errs.append_array(rules_.errors)
	var ids := {}
	var teams := {}
	for e in entities_:
		var ent: CombatEntity = e
		if ent.id == "":
			errs.append("entidad sin id")
		elif ids.has(ent.id):
			errs.append("id de entidad duplicado '%s'" % ent.id)
		ids[ent.id] = true
		if ent.team == "":
			errs.append("entidad '%s' sin equipo" % ent.id)
		teams[ent.team] = true
	if entities_.size() < 2 or teams.size() < 2:
		errs.append("se necesitan al menos dos entidades de equipos distintos")
	for oid in overrides:
		if not ids.has(oid):
			errs.append("override para entidad desconocida '%s'" % str(oid))
	if not errs.is_empty():
		return errs
	catalog = StatusCatalog.new()
	errs.append_array(catalog.load_native(registry))
	for e in entities_:
		var ent: CombatEntity = e
		errs.append_array(catalog.register_all(ent.custom_statuses, registry).map(func(m): return "%s: %s" % [ent.id, m]))
	if errs.is_empty():
		errs.append_array(_validate_status_refs(entities_))
		errs.append_array(_validate_elements(entities_, rules_))
	if not errs.is_empty():
		return errs

	rules = rules_
	seed_value = seed_
	rng = RngService.new(seed_)
	log = EventLog.new(trace)
	scheduler = AtbScheduler.new(rules)
	var slot := 0
	for e in entities_:
		var ent: CombatEntity = e
		ent.slot = slot
		slot += 1
		ent.alive = true
		ent.initiative_micro = 0
		ent.initiative_suspended = false
		ent.hp = ent.hp_max()
		ent.ai_memory = AIMemory.fresh() # la memoria de IA no se comparte entre batallas
		ent.script_vars = {}
		entities.append(ent)
		_by_id[ent.id] = ent
	_apply_overrides(overrides)
	if profile == null:
		profile = BalanceProfile.default_profile()
	status_service = StatusService.new(self)
	status_service.attach()
	defense_service = DefenseService.new(self)
	defense_service.attach()
	trigger_service = TriggerService.new(self)
	for ent in entities:
		AIMemory.ensure(self, ent.ai)
	for ent in entities:
		for ab in ent.abilities:
			_register_ability(ent, ab, "base")
	stats.attach(self)
	end_conditions = [LastTeamStanding.new(), LimitCondition.new()]
	return []


func _validate_status_refs(entities_: Array) -> Array:
	var errs: Array = []
	for e in entities_:
		var ent: CombatEntity = e
		for ab in ent.abilities:
			_check_refs(ab.effects, "%s/%s" % [ent.id, ab.id], errs)
			for ef in ab.effects:
				if str(ef.get("type", "")) == "summon" and not ent.summon_templates.has(str(ef.get("template", ""))):
					errs.append("%s/%s: summon usa la plantilla inexistente '%s'" % [ent.id, ab.id, str(ef.get("template", ""))])
		for id in catalog.ids():
			var d := catalog.get_def(id)
			_check_refs(d.on_apply, "estado %s" % id, errs)
			_check_refs(d.on_expire, "estado %s" % id, errs)
			for p in d.periodic:
				_check_refs(p["effects"], "estado %s" % id, errs)
	var seen := {}
	var uniq: Array = []
	for m in errs:
		if not seen.has(m):
			seen[m] = true
			uniq.append(m)
	return uniq


## Los elementos usados por contenido deben existir en el catalogo del reglamento (`elements`).
func _validate_elements(entities_: Array, rules_: Ruleset) -> Array:
	var errs: Array = []
	var cat: Array = rules_.elements()
	for e in entities_:
		var ent: CombatEntity = e
		for stat in ent.stats.stat_ids():
			_el_stat(str(stat), ent.id, cat, errs)
		for ab in ent.abilities:
			var where := "%s/%s" % [ent.id, ab.id]
			_el_effects(ab.effects, where, cat, errs)
			for m in ab.passive_modifiers:
				_el_stat(str(m.get("stat", "")), where, cat, errs)
		for tmpl in ent.summon_templates.values():
			for st in (tmpl as Dictionary).get("stats", {}):
				_el_stat(str(st), "%s (invocacion)" % ent.id, cat, errs)
			for ab in (tmpl as Dictionary).get("abilities", []):
				_el_ability_dict(ab, "%s (invocacion)" % ent.id, cat, errs)
	for id in catalog.ids():
		if catalog.native_ids.has(id):
			continue
		var d := catalog.get_def(id)
		var where := "estado %s" % id
		for key in ["immune_elements", "absorb_elements"]:
			for el in d.defense.get(key, []):
				_el_check(str(el), where, cat, errs)
		for el in d.defense.get("absorb", {}).get("elements", []):
			_el_check(str(el), where, cat, errs)
		for m in d.modifiers:
			_el_stat(str(m["stat"]), where, cat, errs)
		_el_effects(d.on_apply, where, cat, errs)
		_el_effects(d.on_expire, where, cat, errs)
		for p in d.periodic:
			_el_effects(p["effects"], where, cat, errs)
		for ad in d.form.get("add_abilities", []):
			_el_ability_dict(ad, where, cat, errs)
	var seen := {}
	var uniq: Array = []
	for m in errs:
		if not seen.has(m):
			seen[m] = true
			uniq.append(m)
	return uniq


static func _el_check(el: String, where: String, cat: Array, errs: Array) -> void:
	if el != "" and not cat.has(el):
		errs.append("%s: elemento '%s' no existe en el catalogo del reglamento (%s)" % [where, el, ", ".join(cat)])


static func _el_stat(stat: String, where: String, cat: Array, errs: Array) -> void:
	for pre in ["ELEM_AFF.", "ELEM_RES."]:
		if stat.begins_with(pre):
			_el_check(stat.substr(pre.length()), where, cat, errs)


static func _el_effects(effects: Array, where: String, cat: Array, errs: Array) -> void:
	for ef in effects:
		for c in ef.get("components", []):
			_el_check(str(c.get("element", "")), where, cat, errs)
		if ef.has("effects"):
			_el_effects(ef["effects"], where, cat, errs)


static func _el_ability_dict(ab: Dictionary, where: String, cat: Array, errs: Array) -> void:
	_el_effects(ab.get("effects", []), where, cat, errs)
	for m in ab.get("passive", {}).get("modifiers", []):
		_el_stat(str(m.get("stat", "")), where, cat, errs)


func _check_refs(effects: Array, where: String, errs: Array) -> void:
	for ef in effects:
		if str(ef.get("type", "")) == "apply_status" and not catalog.has(str(ef.get("status", ""))):
			errs.append("%s: apply_status usa el estado inexistente '%s'" % [where, str(ef.get("status", ""))])
		if ef.has("status") and ["remove_status", "extend_status", "transfer_status"].has(str(ef.get("type", ""))) and not catalog.has(str(ef["status"])):
			errs.append("%s: %s usa el estado inexistente '%s'" % [where, str(ef["type"]), str(ef["status"])])


func _apply_overrides(overrides: Dictionary) -> void:
	for oid in overrides:
		var ov: Dictionary = overrides[oid]
		var ent: CombatEntity = _by_id[oid]
		if ov.has("hp"):
			ent.hp = clampf(float(ov["hp"]), 0.0, ent.hp_max())
		if ov.has("initiative"):
			ent.initiative_micro = int(round(float(ov["initiative"]) * Ruleset.TIME_SCALE))
		for rid in ov.get("resources", {}):
			var r: ResourceState = ent.get_resource(str(rid))
			if r != null:
				r.value = clampf(float(ov["resources"][rid]), r.min_value, r.max_value)
		_overrides_applied[oid] = ov.duplicate(true)


# --- Consultas ----------------------------------------------------------------------

func get_entity(id: String) -> CombatEntity:
	return _by_id.get(id, null)


## "self" | "ally" | "enemy". Punto de extension para charm/confusion (fase 3).
func relation(a: CombatEntity, b: CombatEntity) -> String:
	if a == b:
		return "self"
	return "ally" if a.team == b.team else "enemy"


func available_abilities(entity: CombatEntity) -> Array[AbilityDef]:
	return entity.abilities # silencio/bloqueos: fase 3


func is_aborted() -> bool:
	return _aborted


## Diagnostico del aborto tecnico ({code, message, kind}); vacio si no hubo.
func get_error() -> Dictionary:
	return _error


func is_ended() -> bool:
	return state == State.ENDED


func living_entities() -> Array[CombatEntity]:
	var out: Array[CombatEntity] = []
	for e in entities:
		if e.alive:
			out.append(e)
	return out


func snapshot() -> Dictionary:
	var ents := []
	for e in entities:
		ents.append(e.snapshot())
	return {
		"time": float(scheduler.now) / float(Ruleset.TIME_SCALE), "turn": turn_count,
		"actions": action_count, "entities": ents, "rng": rng.get_states(),
	}


func forecast(count: int = 5) -> Array:
	return scheduler.forecast(entities, count)


# --- Formulas --------------------------------------------------------------------------

func eval_formula(text: String, fctx: FormulaContext) -> Dictionary:
	var f: Formula = _formulas.get(text, null)
	if f == null:
		f = Formula.parse(text)
		_formulas[text] = f
	return f.evaluate(fctx.resolver())


# --- Eventos ----------------------------------------------------------------------------

## Emite y registra un evento. Si es PRE, ejecuta los interceptores antes de
## notificar a los observadores. Devuelve el evento (comprobar `cancelled`).
func emit(type: String, source_id: String = "", target_id: String = "", data: Dictionary = {}, cause_id: int = 0, phase: CombatEvent.Phase = CombatEvent.Phase.INFO) -> CombatEvent:
	var ev := _new_event(type, source_id, target_id, data, cause_id, phase)
	if _aborted:
		return ev # tras un aborto no se procesan mas eventos
	if log.count >= rules.max_events():
		abort("max_events", "se supero el limite de eventos (%d)" % rules.max_events())
		return ev
	if _depth >= rules.max_event_depth():
		abort("max_event_depth", "profundidad de eventos excedida (%d)" % rules.max_event_depth())
		return ev
	_depth += 1
	log.record(ev)
	if phase == CombatEvent.Phase.PRE:
		_run_interceptors(ev)
	if not _aborted:
		for sub in dispatcher.observers_for(type):
			(sub["fn"] as Callable).call(ev, self)
			if _aborted:
				break
	_depth -= 1
	return ev


func _new_event(type: String, source_id: String, target_id: String, data: Dictionary, cause_id: int, phase: CombatEvent.Phase) -> CombatEvent:
	var ev := CombatEvent.new()
	_event_seq += 1
	ev.id = _event_seq
	ev.type = type
	ev.time = scheduler.now if scheduler != null else 0
	ev.phase = phase
	ev.source_id = source_id
	ev.target_id = target_id
	ev.cause_id = cause_id
	ev.data = data
	return ev


func _run_interceptors(ev: CombatEvent) -> void:
	for sub in dispatcher.interceptors_for(ev.type):
		var mods_before: int = ev.modifications.size()
		(sub["fn"] as Callable).call(ev, self)
		for i in range(mods_before, ev.modifications.size()):
			var m: Dictionary = ev.modifications[i]
			emit(EventTypes.EVENT_MODIFIED, str(m["by"]), ev.target_id, {
				"event": ev.id, "key": m["key"], "old": m["old"], "new": m["new"],
			}, ev.id)
		if ev.cancelled:
			emit(EventTypes.EVENT_CANCELLED, ev.cancelled_by, ev.target_id, {
				"event": ev.id, "type": ev.type, "reason": ev.cancel_reason,
			}, ev.id)
			return
		if _aborted:
			return


# --- Estado: vida y muerte -------------------------------------------------------------

func _set_hp_silent(entity: CombatEntity, new_hp: float) -> void:
	if new_hp != entity.hp:
		last_hp_change_turn = turn_count
	entity.hp = clampf(new_hp, 0.0, maxf(entity.hp_max(), 0.0))


func _emit_hp_changed(entity: CombatEntity, old: float, reason: String, cause_id: int) -> void:
	if entity.hp != old:
		emit(EventTypes.HP_CHANGED, entity.last_damage_source, entity.id, {
			"old": old, "new": entity.hp, "delta": entity.hp - old, "reason": reason,
		}, cause_id)


## Cambia la vida (acotada a [0, HP max]) y emite HP_CHANGED.
func change_hp(entity: CombatEntity, delta: float, reason: String, cause_id: int = 0) -> float:
	var old := entity.hp
	var new_hp := clampf(old + delta, 0.0, entity.hp_max())
	entity.hp = new_hp
	if new_hp != old:
		last_hp_change_turn = turn_count
		emit(EventTypes.HP_CHANGED, entity.last_damage_source, entity.id, {
			"old": old, "new": new_hp, "delta": new_hp - old, "reason": reason,
		}, cause_id)
	return new_hp - old


## Comprueba la muerte de una entidad (inmediata al llegar a 0 de vida).
## La victoria NO se evalua aqui, sino al terminar la accion (punto seguro).
func check_death(entity: CombatEntity, cause_id: int = 0) -> void:
	if not entity.alive or entity.hp > 0.0:
		return
	var pre := emit(EventTypes.DEATH_PRE, entity.last_damage_source, entity.id, {"hp": entity.hp}, cause_id, CombatEvent.Phase.PRE)
	if pre.cancelled:
		if entity.hp <= 0.0:
			var survive: float = minf(float(rules.get_path_value("damage.survive_hp")), entity.hp_max())
			change_hp(entity, survive - entity.hp, "death_prevented", pre.id)
		return
	entity.alive = false
	emit(EventTypes.DEATH, entity.last_damage_source, entity.id, {"killer": entity.last_damage_source}, pre.id)
	interrupt_channel(entity, "death")
	status_service.clear_all(entity, "death")
	_despawn_owned(entity, "owner_death")


func check_all_deaths(cause_id: int = 0) -> void:
	for e in entities:
		check_death(e, cause_id)


## Tiradas de impacto/critico del ataque. Siempre desde los flujos "hit"/"crit".
## La tirada de impacto se consume salvo `always_hit`; la de critico siempre que
## haya impacto y `can_crit` (mantiene estables las secuencias).
func roll_attack(actor: CombatEntity, target: CombatEntity, always_hit: bool, can_crit: bool, crit_bonus: float, cause_id: int) -> Dictionary:
	var hit := true
	var chance := 1.0
	var roll := -1.0
	if not always_hit:
		chance = DamageCalculator.hit_chance(rules, actor, target)
		roll = rng.stream("hit").next_float()
		hit = roll < chance
	if not hit:
		emit(EventTypes.MISS, actor.id, target.id, {"chance": chance, "roll": roll}, cause_id)
		return {"hit": false, "crit": false}
	emit(EventTypes.HIT, actor.id, target.id, {"chance": chance, "roll": roll, "forced": always_hit}, cause_id)
	var crit := false
	if can_crit:
		var cc: float = clampf(DamageCalculator.crit_chance(rules, actor) + crit_bonus, 0.0, 1.0)
		var croll: float = rng.stream("crit").next_float()
		crit = croll < cc
		if crit:
			emit(EventTypes.CRIT, actor.id, target.id, {"chance": cc, "roll": croll, "kind": "damage"}, cause_id)
	return {"hit": true, "crit": crit}


# --- Dano y curacion resueltos (punto unico de entrada) -----------------------------------------------

## Entrega dano ya calculado: damage_pre (PRE, interceptable) -> damage_dealt -> hp_changed -> muerte.
## `info`: component, damage_type, element, crit, base, premitigation, defense_used,
## resistance_used, amount, y opcionalmente reflected (bool).
func deliver_damage(actor: CombatEntity, target: CombatEntity, info: Dictionary, cause_id: int) -> void:
	var pre_data := info.duplicate()
	pre_data["reflected"] = bool(info.get("reflected", false))
	var pre := emit(EventTypes.DAMAGE_PRE, actor.id, target.id, pre_data, cause_id, CombatEvent.Phase.PRE)
	if pre.cancelled:
		return
	var amount: float = maxf(float(pre.data["amount"]), 0.0)
	var hp_before: float = target.hp
	var applied: float = minf(amount, target.hp)
	target.last_damage_source = actor.id
	# La vida se aplica ANTES de notificar damage_dealt: las reacciones ven el estado posterior
	# (una entidad a 0 de vida sigue "viva" hasta resolverse la muerte; D-043).
	_set_hp_silent(target, hp_before - applied)
	var dealt := emit(EventTypes.DAMAGE_DEALT, actor.id, target.id, {
		"component": int(info.get("component", 0)), "damage_type": str(info["damage_type"]), "element": str(info.get("element", "")),
		"crit": bool(info.get("crit", false)), "intended": info["base"], "premitigation": info["premitigation"],
		"mitigated": maxf(float(info["premitigation"]) - amount, 0.0),
		"amount": amount, "applied": applied, "overkill": amount - applied,
		"hp_before": hp_before, "hp_after": hp_before - applied, "reflected": bool(pre.data["reflected"]),
	}, pre.id, CombatEvent.Phase.POST)
	_emit_hp_changed(target, hp_before, "damage", dealt.id)
	check_death(target, dealt.id)


## Curacion directa (absorcion elemental, restauraciones): aplica HEAL_REC y limita a la vida faltante.
func direct_heal(actor: CombatEntity, target: CombatEntity, raw: float, reason: String, cause_id: int) -> void:
	var amount := DamageCalculator.heal_amount(rules, target, raw)
	var pre := emit(EventTypes.HEAL_PRE, actor.id, target.id, {"raw": raw, "amount": amount, "crit": false, "reason": reason}, cause_id, CombatEvent.Phase.PRE)
	if pre.cancelled:
		return
	amount = maxf(float(pre.data["amount"]), 0.0)
	var applied := minf(amount, maxf(target.hp_max() - target.hp, 0.0))
	var done := emit(EventTypes.HEAL_DONE, actor.id, target.id, {
		"raw": raw, "amount": amount, "applied": applied, "overheal": amount - applied, "crit": false,
		"hp_before": target.hp, "hp_after": target.hp + applied, "reason": reason,
	}, pre.id)
	change_hp(target, applied, "heal", done.id)


## Crea una entidad en mitad del combate (invocacion). Devuelve null si se supera un limite.
func add_entity(entity: CombatEntity, cause_id: int = 0) -> CombatEntity:
	var errs: Array = []
	for d in entity.custom_statuses:
		if not catalog.has(str(d.get("id", ""))):
			errs.append_array(catalog.register_all([d], registry))
	errs.append_array(_validate_status_refs([entity]))
	errs.append_array(_validate_elements([entity], rules))
	if not errs.is_empty():
		abort("summon_invalid", "; ".join(errs))
		return null
	entity.slot = entities.size()
	entity.alive = true
	entity.initiative_micro = 0
	entity.hp = entity.hp_max()
	entity.ai_memory = AIMemory.fresh()
	entity.script_vars = {}
	AIMemory.ensure(self, entity.ai)
	entities.append(entity)
	_by_id[entity.id] = entity
	for ab in entity.abilities:
		_register_ability(entity, ab, "summon")
	emit(EventTypes.SUMMON_CREATED, entity.owner_id, entity.id, {"template": entity.content_ref.get("template", ""), "team": entity.team}, cause_id)
	return entity


func add_metric(name: String, entity_id: String, amount: float) -> void:
	if not custom_metrics.has(name):
		if custom_metrics.size() >= 64:
			return # limite tecnico de metricas distintas
		custom_metrics[name] = {"total": 0.0, "count": 0, "by_entity": {}}
	var m: Dictionary = custom_metrics[name]
	m["total"] = float(m["total"]) + amount
	m["count"] = int(m["count"]) + 1
	m["by_entity"][entity_id] = float(m["by_entity"].get(entity_id, 0.0)) + amount


func owned_alive(owner: CombatEntity) -> Array[CombatEntity]:
	var out: Array[CombatEntity] = []
	for e in entities:
		if e.alive and e.owner_id == owner.id:
			out.append(e)
	return out


# --- Recursos, iniciativa, vida maxima ------------------------------------------------------------

## Cambia un recurso (acotado) y emite resource_changed (+ resource_limit al tocar un limite).
func change_resource(entity: CombatEntity, rid: String, delta: float, reason: String, cause_id: int = 0) -> float:
	var r: ResourceState = entity.get_resource(rid)
	if r == null:
		return 0.0
	var old := r.value
	var applied := r.change(delta)
	emit(EventTypes.RESOURCE_CHANGED, entity.id, entity.id, {
		"resource": rid, "old": old, "new": r.value, "delta": applied, "reason": reason,
	}, cause_id)
	if r.value != old:
		if r.value >= r.max_value and old < r.max_value:
			emit(EventTypes.RESOURCE_LIMIT, entity.id, entity.id, {"resource": rid, "limit": "max", "value": r.value}, cause_id)
		elif r.value <= r.min_value and old > r.min_value:
			emit(EventTypes.RESOURCE_LIMIT, entity.id, entity.id, {"resource": rid, "limit": "min", "value": r.value}, cause_id)
	return applied


func change_resource_max(entity: CombatEntity, rid: String, new_max: float, cause_id: int = 0) -> void:
	var r: ResourceState = entity.get_resource(rid)
	if r == null:
		return
	var old_max := r.max_value
	var old := r.value
	r.max_value = maxf(new_max, r.min_value)
	r.value = clampf(r.value, r.min_value, r.max_value)
	emit(EventTypes.RESOURCE_CHANGED, entity.id, entity.id, {
		"resource": rid, "old": old, "new": r.value, "delta": r.value - old, "reason": "max_changed",
		"old_max": old_max, "new_max": r.max_value,
	}, cause_id)


## Cambia la iniciativa (microunidades); nunca baja de 0.
func change_initiative(entity: CombatEntity, delta_micro: int, reason: String, by_id: String, cause_id: int = 0) -> void:
	var old := entity.initiative_micro
	entity.initiative_micro = maxi(old + delta_micro, 0)
	emit(EventTypes.INITIATIVE_CHANGED, by_id, entity.id, {
		"old": float(old) / float(Ruleset.TIME_SCALE), "new": float(entity.initiative_micro) / float(Ruleset.TIME_SCALE), "reason": reason,
	}, cause_id)


## Si la vida actual supera la maxima (tras bajar HP max), la acota.
func clamp_hp(entity: CombatEntity) -> void:
	var m := entity.hp_max()
	if entity.hp > m:
		change_hp(entity, m - entity.hp, "max_hp_changed")


# --- Habilidades dinamicas, canalizacion, invocaciones ----------------------------------------

## Registra pasivas (modificadores) y disparadores de una habilidad de la entidad.
func _register_ability(entity: CombatEntity, ability: AbilityDef, source: String) -> void:
	AbilityRuntime.state(entity, ability)
	if ability.is_triggered() and trigger_service != null:
		trigger_service.register(entity, ability)
	var src := "passive:" + ability.id
	for m in ability.passive_modifiers:
		entity.stats.add_modifier(StatModifier.make(str(m["stat"]), StatusDef.KINDS[str(m["kind"])], float(m["value"]), src, int(m.get("priority", 0))))
	if not ability.passive_modifiers.is_empty():
		clamp_hp(entity)


func add_ability(entity: CombatEntity, ability: AbilityDef, source: String = "effect") -> void:
	entity.abilities.append(ability)
	_register_ability(entity, ability, source)


func remove_ability(entity: CombatEntity, ability_id: String) -> bool:
	var ab := entity.get_ability(ability_id)
	if ab == null:
		return false
	entity.abilities.erase(ab)
	if trigger_service != null:
		trigger_service.unregister(entity, ability_id)
	entity.stats.remove_by_source("passive:" + ability_id)
	entity.cooldowns.erase(ability_id)
	clamp_hp(entity)
	return true


func begin_channel(actor: CombatEntity, ability: AbilityDef, targets: Array[CombatEntity], ctx: ActionContext) -> void:
	var ids: Array = []
	for t in targets:
		ids.append(t.id)
	var at: int = scheduler.now + int(round(ability.cast_time * Ruleset.TIME_SCALE))
	var aid := actor.id
	var timer := scheduler.schedule(at, func(_e): _complete_channel(aid), "channel_complete", {"actor": aid, "ability": ability.id})
	actor.channel = {"ability": ability.id, "targets": ids, "completes_at": at, "cause": ctx.cause_id,
		"interruptible": ability.interruptible, "timer": timer}
	actor.suspension_sources["channel"] = true
	emit(EventTypes.CHANNEL_STARTED, actor.id, ids[0] if not ids.is_empty() else "", {
		"ability": ability.id, "completes_at": float(at) / float(Ruleset.TIME_SCALE), "interruptible": ability.interruptible,
	}, ctx.cause_id)


func _complete_channel(actor_id: String) -> void:
	var a := get_entity(actor_id)
	if a == null or a.channel.is_empty():
		return
	var ch: Dictionary = a.channel
	a.channel = {}
	a.suspension_sources.erase("channel")
	if not a.alive:
		return
	var ab := a.get_ability(str(ch["ability"]))
	if ab == null:
		return
	emit(EventTypes.CHANNEL_COMPLETED, a.id, "", {"ability": ab.id}, int(ch["cause"]))
	var ctx := ActionContext.new()
	ctx.engine = self
	ctx.actor = a
	ctx.ability = ab
	ctx.cause_id = int(ch["cause"])
	for tid in ch["targets"]:
		var t := get_entity(str(tid))
		if t != null:
			ctx.targets.append(t)
	var prev := current_action_started_id
	current_action_started_id = ctx.cause_id
	ActionResolver.run_effects(self, ctx, ab.effects)
	if not is_aborted():
		emit(EventTypes.ACTION_RESOLVED, a.id, str(ch["targets"][0]) if not ch["targets"].is_empty() else "", {"ability": ab.id}, ctx.cause_id)
	current_action_started_id = prev


## Interrumpe la canalizacion en curso. `death` siempre interrumpe; el resto solo si es interrumpible.
func interrupt_channel(entity: CombatEntity, by: String) -> bool:
	if entity.channel.is_empty():
		return false
	if not bool(entity.channel["interruptible"]) and by != "death":
		return false
	scheduler.cancel_timed(int(entity.channel["timer"]))
	var ab: String = str(entity.channel["ability"])
	entity.channel = {}
	entity.suspension_sources.erase("channel")
	emit(EventTypes.CHANNEL_INTERRUPTED, by, entity.id, {"ability": ab, "by": by}, 0)
	return true


func _despawn_owned(owner: CombatEntity, reason: String) -> void:
	if str(rules.get_path_value("summons.on_owner_death")) != "despawn":
		return
	for e in owned_alive(owner):
		despawn(e, reason, 0)


## Retira una entidad del combate sin pasar por la muerte por dano (vida de invocacion agotada, etc.).
func despawn(entity: CombatEntity, reason: String, cause_id: int = 0) -> void:
	if not entity.alive:
		return
	entity.alive = false
	entity.hp = 0.0
	emit(EventTypes.ENTITY_DESPAWNED, entity.owner_id, entity.id, {"reason": reason}, cause_id)
	interrupt_channel(entity, "death")
	status_service.clear_all(entity, "despawn")
	_despawn_owned(entity, "owner_despawn")


# --- Bucle principal ----------------------------------------------------------------------

func start() -> void:
	if state != State.NEW:
		return
	state = State.RUNNING
	var ents: Array = []
	for e in entities:
		var info := {"id": e.id, "team": e.team, "slot": e.slot, "hp": e.hp, "hp_max": e.hp_max(),
			"stats": e.stats.effective_map(), "ai": e.ai.ai_id() if e.ai != null else "none",
			"abilities": e.abilities.map(func(a): return a.id), "content": e.content_ref}
		if not e.scripts.is_empty():
			var hashes := {}
			for sid in e.scripts:
				hashes[sid] = (e.scripts[sid] as ScriptProgram).source_hash # huella de cada script: trazabilidad
			info["scripts"] = hashes
		ents.append(info)
	emit(EventTypes.COMBAT_STARTED, "", "", {
		"seed": seed_value, "engine_version": ENGINE_VERSION, "ruleset_id": rules.id(),
		"ruleset_version": rules.version(), "ruleset_hash": rules.content_hash(),
		"entities": ents, "initial_overrides": _overrides_applied,
	})


## Avanza un paso. Devuelve true mientras el combate siga en marcha.
func step() -> bool:
	if state == State.ENDED:
		return false
	if state == State.NEW:
		start()
	if _cancel_requested:
		abort("cancelled", "cancelado por el usuario", "cancelled")
	if not _aborted:
		if turn == null:
			_begin_next_turn()
		else:
			_process_decision()
	if _aborted and state != State.ENDED:
		_finish_aborted()
	return state != State.ENDED


func run() -> CombatResult:
	while step():
		pass
	return result


## Solicita cancelar; el combate termina como ABORTED en el siguiente paso.
func request_cancel() -> void:
	_cancel_requested = true


## Aborto tecnico: el combate termina como ABORTED con diagnostico (nunca como
## derrota o empate silencioso).
func abort(code: String, message: String, kind: String = "technical") -> void:
	if _aborted:
		return
	_aborted = true
	_error = {"code": code, "message": message, "kind": kind}
	var ev := _new_event(EventTypes.ERROR, "", "", {"code": code, "message": message}, 0, CombatEvent.Phase.INFO)
	log.record(ev) # directo: ignora limites para conservar el diagnostico


func _begin_next_turn() -> void:
	var limits := _evaluate_end("turn_boundary")
	if not limits.is_empty():
		_finish(limits)
		return
	while state == State.RUNNING and not _aborted:
		var plan := scheduler.plan(entities)
		if plan["kind"] == "none":
			_finish({"outcome": CombatResult.DRAW, "winner_team": "", "reason": "no_actor_can_act", "kind": "stalemate"})
			return
		var max_micro := int(round(float(rules.get_path_value("victory.limits.max_virtual_time")) * Ruleset.TIME_SCALE))
		if int(plan["time"]) > max_micro:
			_finish(LimitCondition.resolve_limit(self, "max_virtual_time"))
			return
		_advance_time(int(plan["time"]))
		if plan["kind"] == "timed":
			_fire_timed_events()
			if _aborted:
				return
			var ended := _evaluate_end("after_action")
			if not ended.is_empty():
				_finish(ended)
				return
			continue
		var ready := scheduler.ready_entities(entities, rng.stream("tiebreak"))
		if ready.is_empty():
			continue
		_begin_turn(ready[0])
		return


func _advance_time(target: int) -> void:
	var dt := target - scheduler.now
	if dt <= 0:
		return
	var from := scheduler.now
	scheduler.advance(entities, dt)
	emit(EventTypes.TIME_ADVANCED, "", "", {"dt": dt, "from": from, "to": scheduler.now})


func _fire_timed_events() -> void:
	var due := scheduler.pop_timed_due(scheduler.now)
	while not due.is_empty() and not _aborted:
		emit(EventTypes.TIMED_EVENT, "", "", {"label": due["label"], "data": due["data"]})
		(due["fn"] as Callable).call(self)
		due = scheduler.pop_timed_due(scheduler.now)


func _begin_turn(e: CombatEntity) -> void:
	e.initiative_micro -= scheduler.threshold
	turn_count += 1
	turn = TurnState.new(e, turn_count)
	var ev := emit(EventTypes.TURN_STARTED, e.id, "", {
		"turn": turn_count, "initiative_after": float(e.initiative_micro) / float(Ruleset.TIME_SCALE),
	}, 0, CombatEvent.Phase.PRE)
	turn.start_event_id = ev.id
	if ev.cancelled:
		emit(EventTypes.TURN_SKIPPED, e.id, "", {"turn": turn_count, "by": ev.cancelled_by}, ev.id)
		_end_turn("skipped")


func _end_turn(reason: String) -> void:
	if turn == null:
		return
	var t := turn
	turn = null
	emit(EventTypes.TURN_ENDED, t.entity.id, "", {
		"turn": t.number, "reason": reason, "actions": t.actions_taken,
	}, t.start_event_id)


func _process_decision() -> void:
	var e := turn.entity
	var pre_end := _evaluate_end("pre_decision")
	if not pre_end.is_empty():
		_end_turn("limit")
		_finish(pre_end)
		return
	if not e.alive:
		_end_turn("actor_dead")
		return
	if turn.actions_taken >= rules.max_actions_per_turn():
		emit(EventTypes.LIMIT_REACHED, e.id, "", {"limit": "max_actions_per_turn"}, turn.start_event_id)
		_end_turn("action_limit")
		return

	var view := ViewBuilder.build(self, e, turn)
	var decision: AIDecision = e.ai.decide(view) if e.ai != null else AIDecision.wait("no_ai")
	if decision == null:
		decision = AIDecision.wait("ia_devolvio_null")
		emit(EventTypes.AI_FALLBACK, e.id, "", {"reason": "decision_null", "policy": "wait"}, turn.start_event_id)
	if decision.fallback != "":
		emit(EventTypes.AI_FALLBACK, e.id, "", {"reason": decision.fallback, "policy": "wait"}, turn.start_event_id)
	var first_target: String = decision.target_ids[0] if not decision.target_ids.is_empty() else ""
	var sel := emit(EventTypes.ACTION_SELECTED, e.id, first_target, decision.to_dict(), turn.start_event_id)

	if decision.kind == AIDecision.Kind.WAIT:
		AIMemory.apply_ops(e, decision.memory_ops)
		emit(EventTypes.WAIT, e.id, "", {"reason": decision.reason}, sel.id)
		_end_turn("wait")
		return

	var err := ActionValidator.validate(self, e, turn, decision)
	if err != "":
		emit(EventTypes.ACTION_REJECTED, e.id, first_target, {"ability": decision.ability_id, "error": err}, sel.id)
		emit(EventTypes.AI_FALLBACK, e.id, "", {"reason": err, "policy": "wait"}, sel.id)
		_end_turn("fallback")
		return

	AIMemory.apply_ops(e, decision.memory_ops)
	var ability := e.get_ability(decision.ability_id)
	var targets: Array[CombatEntity] = []
	for tid in decision.target_ids:
		targets.append(_by_id[tid])
	turn.actions_taken += 1
	action_count += 1
	ActionResolver.resolve(self, turn, e, ability, targets, sel.id)
	if _aborted:
		return
	var ended := _evaluate_end("after_action")
	if not ended.is_empty():
		_end_turn("combat_end")
		_finish(ended)
		return
	if not e.alive:
		_end_turn("actor_dead")
	elif not e.channel.is_empty():
		_end_turn("channeling")
	elif ActionValidator.legal_actions(self, e, turn).is_empty():
		_end_turn("no_more_actions")


func _evaluate_end(point: String) -> Dictionary:
	for c in end_conditions:
		var r := c.evaluate(self, point)
		if not r.is_empty():
			return r
	return {}


# --- Finalizacion ---------------------------------------------------------------------------

func _finish(decision: Dictionary) -> void:
	if state == State.ENDED:
		return
	emit(EventTypes.LIMIT_REACHED if decision["kind"] == "limit" else EventTypes.COMBAT_ENDED, "", "", {
		"outcome": decision["outcome"], "winner_team": decision["winner_team"],
		"reason": decision["reason"], "kind": decision["kind"],
	})
	if decision["kind"] == "limit":
		emit(EventTypes.COMBAT_ENDED, "", "", {
			"outcome": decision["outcome"], "winner_team": decision["winner_team"],
			"reason": decision["reason"], "kind": decision["kind"],
		})
	if _aborted:
		return # un aborto durante el cierre lo gestiona step()
	_build_result(decision)


func _finish_aborted() -> void:
	var ev := _new_event(EventTypes.COMBAT_ENDED, "", "", {
		"outcome": CombatResult.ABORTED, "winner_team": "", "reason": _error["code"], "kind": _error["kind"],
	}, 0, CombatEvent.Phase.INFO)
	log.record(ev)
	_build_result({"outcome": CombatResult.ABORTED, "winner_team": "", "reason": _error["code"], "kind": _error["kind"]})
	result.error = {"code": _error["code"], "message": _error["message"]}


## Libera referencias circulares (motor <-> servicios/closures) para que la memoria
## se recupere al terminar un combate (imprescindible en lotes). Se llama sola al
## finalizar; el registro, las entidades y el resultado siguen disponibles, pero el
## motor ya no admite nuevas acciones.
func dispose() -> void:
	dispatcher.clear()
	defense_service = null
	trigger_service = null
	if scheduler != null:
		scheduler.clear_timed()
	status_service = null
	_formulas.clear()


func _build_result(decision: Dictionary) -> void:
	state = State.ENDED
	turn = null
	var r := CombatResult.new()
	r.outcome = decision["outcome"]
	r.winner_team = decision["winner_team"]
	r.reason = decision["reason"]
	r.kind = decision["kind"]
	r.seed_value = seed_value
	r.engine_version = ENGINE_VERSION
	r.ruleset_id = rules.id()
	r.ruleset_version = rules.version()
	r.ruleset_hash = rules.content_hash()
	r.end_time = float(scheduler.now) / float(Ruleset.TIME_SCALE)
	r.turns = turn_count
	r.actions = action_count
	r.events = log.count
	r.log_hash = log.digest()
	for e in entities:
		r.entities[e.id] = {"team": e.team, "alive": e.alive, "hp": e.hp}
	r.stats = stats.to_dict()
	r.metrics = custom_metrics.duplicate(true)
	result = r
	dispose()
