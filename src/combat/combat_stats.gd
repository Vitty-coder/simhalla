class_name CombatStats
extends RefCounted
## Contadores por entidad calculados a partir de los eventos (observador).
##
## Separa dano intentado, premitigacion, efectivo y sobreexceso para evitar
## doble conteo. Funciona igual con traza reducida (no lee el registro).

var per_entity: Dictionary = {}
var _active: Dictionary = {} ## id de action_started -> {actor, ability}: atribucion de dano/curacion a la habilidad en curso
const OTHER := "(otros)" ## dano/curacion sin accion en curso (periodicos, reflejos...)


func attach(engine: CombatEngine) -> void:
	engine.dispatcher.observe("*", Callable(self, "_on_event"), -1000, "combat_stats")


func _ent(id: String) -> Dictionary:
	if id == "":
		return {}
	if not per_entity.has(id):
		per_entity[id] = {
			"damage_dealt": 0.0, "damage_taken": 0.0, "damage_intended": 0.0,
			"damage_premitigation": 0.0, "damage_mitigated": 0.0, "overkill": 0.0,
			"healing_done": 0.0, "healing_received": 0.0, "overheal": 0.0,
			"hits": 0, "misses": 0, "crits": 0, "dodged": 0,
			"turns": 0, "actions": 0, "waits": 0, "kills": 0, "abilities": {},
		}
	return per_entity[id]


## Estadisticas por (entidad, habilidad): usos, interrupciones, dano y curacion EFECTIVOS atribuidos.
func _ab(entity_id: String, ability: String) -> Dictionary:
	var abs: Dictionary = _ent(entity_id)["abilities"]
	if not abs.has(ability):
		abs[ability] = {"uses": 0, "interrupted": 0, "damage_dealt": 0.0, "healing_done": 0.0, "crits": 0}
	return abs[ability]


func _current_ability(engine: CombatEngine) -> String:
	var a: Variant = _active.get(engine.current_action_started_id, null)
	return str(a["ability"]) if a != null else OTHER


func _on_event(ev: CombatEvent, engine: CombatEngine) -> void:
	match ev.type:
		EventTypes.ACTION_STARTED:
			if ev.cancelled:
				_ab(ev.source_id, str(ev.data.get("ability", "?")))["interrupted"] += 1
			else:
				_active[ev.id] = {"actor": ev.source_id, "ability": str(ev.data.get("ability", "?"))}
		EventTypes.ACTION_RESOLVED:
			_ab(ev.source_id, str(ev.data.get("ability", "?")))["uses"] += 1
			_active.erase(ev.cause_id)
		EventTypes.ACTION_INTERRUPTED:
			_active.erase(ev.cause_id)
		EventTypes.TURN_STARTED:
			if not ev.cancelled:
				_ent(ev.source_id)["turns"] += 1
		EventTypes.ACTION_RESOLVED:
			_ent(ev.source_id)["actions"] += 1
		EventTypes.WAIT:
			_ent(ev.source_id)["waits"] += 1
		EventTypes.HIT:
			_ent(ev.source_id)["hits"] += 1
		EventTypes.MISS:
			_ent(ev.source_id)["misses"] += 1
			_ent(ev.target_id)["dodged"] += 1
		EventTypes.CRIT:
			_ent(ev.source_id)["crits"] += 1
		EventTypes.DAMAGE_DEALT:
			var d := ev.data
			var a := _ent(ev.source_id)
			var t := _ent(ev.target_id)
			a["damage_dealt"] += float(d["applied"])
			a["damage_intended"] += float(d["intended"])
			a["damage_premitigation"] += float(d["premitigation"])
			a["damage_mitigated"] += float(d["mitigated"])
			a["overkill"] += float(d["overkill"])
			t["damage_taken"] += float(d["applied"])
			var dab := _ab(ev.source_id, _current_ability(engine))
			dab["damage_dealt"] += float(d["applied"])
			if bool(d.get("crit", false)):
				dab["crits"] += 1
		EventTypes.HEAL_DONE:
			_ent(ev.source_id)["healing_done"] += float(ev.data["applied"])
			_ent(ev.target_id)["healing_received"] += float(ev.data["applied"])
			_ent(ev.source_id)["overheal"] += float(ev.data["overheal"])
			_ab(ev.source_id, _current_ability(engine))["healing_done"] += float(ev.data["applied"])
		EventTypes.DEATH:
			if ev.source_id != "" and ev.source_id != ev.target_id:
				_ent(ev.source_id)["kills"] += 1


func to_dict() -> Dictionary:
	return per_entity.duplicate(true)
