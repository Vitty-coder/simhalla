class_name CombatEntity
extends RefCounted
## Participante de un combate (PJ, invocacion, torreta...). Estado runtime.
##
## No hay clases por personaje: todo el comportamiento sale de datos
## (estadisticas, habilidades, recursos, etiquetas, IA). La entidad no sabe
## nada de la UI ni del motor.

var id: String = ""
var display_name: String = ""
var team: String = ""
var owner_id: String = "" ## Para invocaciones (fase 3).
var counts_for_victory: bool = true ## false para invocaciones auxiliares.
var slot: int = 0 ## Orden de alta en el combate (desempates estables).

var stats: StatSet = StatSet.new()
var hp: float = 0.0
var initiative_micro: int = 0
var initiative_suspended: bool = false
var alive: bool = true

var resources: Dictionary = {} ## id -> ResourceState
var abilities: Array[AbilityDef] = []
var tags: Array[String] = []
var ai: AIController = null
var scripts: Dictionary = {} ## id -> ScriptProgram (compilados; solo datos)
var script_vars: Dictionary = {} ## variables de los scripts durante el combate (se reinician por combate)
var ai_memory: Dictionary = {} ## Memoria de IA durante el combate (no se comparte).
var last_damage_source: String = ""

# --- Fase 3 ---
var statuses: Array[StatusInstance] = []
var cooldowns: Dictionary = {} ## ability_id -> Duration
var ability_state: Dictionary = {} ## ability_id -> {"uses_combat","uses_turn","turn","charges"}
var custom_statuses: Array = [] ## definiciones (dict) de estados propios del PJ
var summon_templates: Dictionary = {} ## id -> datos de entidad (dict)
var suspension_sources: Dictionary = {} ## origen -> true (estados/canalizacion que suspenden la iniciativa)
var prev_action: Dictionary = {} ## accion anterior a la ultima (repeat_action)
var last_action: Dictionary = {} ## {"ability", "targets"} de la ultima accion propia
var stored_states: Dictionary = {} ## clave -> instantanea (record_state)
var channel: Dictionary = {} ## canalizacion en curso (vacio si no hay)
var lifespan: Duration = null ## vida limitada de una invocacion
var summon_depth: int = 0
var passive_source_ids: Array[String] = []
var content_ref: Dictionary = {} ## Metadatos de origen (id/version/hash), fase 2.


func is_suspended() -> bool:
	return initiative_suspended or not suspension_sources.is_empty()


func status_stacks(status_id: String) -> int:
	var n := 0
	for st in statuses:
		if st.def.id == status_id:
			n += st.stacks
	return n


func has_status_flag(flag: String) -> bool:
	for st in statuses:
		if not st.frozen and st.def.flags.get(flag, false):
			return true
	return false


func suspends_cooldowns() -> bool:
	for st in statuses:
		if not st.frozen and st.def.flags.get("suspend_cooldowns", false):
			return true
	return false


func hp_max() -> float:
	return stats.get_value("HP")


func hp_ratio() -> float:
	var m := hp_max()
	return hp / m if m > 0.0 else 0.0


func get_ability(ability_id: String) -> AbilityDef:
	for a in abilities:
		if a.id == ability_id:
			return a
	return null


func has_tag(tag: String) -> bool:
	return tags.has(tag)


func get_resource(resource_id: String) -> ResourceState:
	return resources.get(resource_id, null)


## Estado serializable completo (depurador, snapshots, informes).
func snapshot() -> Dictionary:
	var res := {}
	var ids: Array = resources.keys()
	ids.sort()
	for r in ids:
		res[r] = (resources[r] as ResourceState).value
	return {
		"id": id, "team": team, "alive": alive, "hp": hp, "hp_max": hp_max(),
		"initiative": float(initiative_micro) / float(Ruleset.TIME_SCALE),
		"suspended": initiative_suspended, "resources": res,
		"stats": stats.effective_map(),
		"statuses": statuses.map(func(st): return st.to_dict()),
		"cooldowns": cooldowns.keys(),
	}
