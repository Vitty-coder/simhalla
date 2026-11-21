class_name StatSet
extends RefCounted
## Estadisticas base + modificadores -> valores efectivos.
##
## Cualquier identificador de estadistica es valido (estadisticas
## personalizadas). Las afinidades/resistencias elementales se guardan como
## "ELEM_AFF.<elemento>" / "ELEM_RES.<elemento>". Una estadistica ausente vale 0.
##
## Orden de combinacion (documentado en docs/COMBAT_RULES.md):
##   1. SET: si existe, sustituye la base (mayor prioridad; empate -> mas reciente).
##   2. (valor + suma FLAT) * (1 + suma PCT_ADD) * producto MULT
##   3. suelo = max(MIN), techo = min(MAX). El techo prevalece si hay conflicto.

var _base: Dictionary = {}
var _mods: Array[StatModifier] = []
var _cache: Dictionary = {}
var _next_seq: int = 1


func set_base(stat: String, value: float) -> void:
	_base[stat] = value
	_cache.clear()


func get_base(stat: String) -> float:
	return float(_base.get(stat, 0.0))


func has_stat(stat: String) -> bool:
	return _base.has(stat)


func stat_ids() -> Array:
	var ids: Array = _base.keys()
	for m in _mods:
		if not ids.has(m.stat):
			ids.append(m.stat)
	ids.sort()
	return ids


func add_modifier(m: StatModifier) -> StatModifier:
	m.seq = _next_seq
	_next_seq += 1
	if m.id == "":
		m.id = "mod#%d" % m.seq
	_mods.append(m)
	_cache.clear()
	return m


func remove_modifier(mod_id: String) -> bool:
	for i in _mods.size():
		if _mods[i].id == mod_id:
			_mods.remove_at(i)
			_cache.clear()
			return true
	return false


## Elimina todos los modificadores de un origen (expiracion ordenada).
func remove_by_source(source_id: String) -> int:
	var removed := 0
	var i := _mods.size() - 1
	while i >= 0:
		if _mods[i].source_id == source_id:
			_mods.remove_at(i)
			removed += 1
		i -= 1
	if removed > 0:
		_cache.clear()
	return removed


func modifiers_for(stat: String) -> Array[StatModifier]:
	var out: Array[StatModifier] = []
	for m in _mods:
		if m.stat == stat:
			out.append(m)
	return out


func get_value(stat: String) -> float:
	if _cache.has(stat):
		return _cache[stat]
	var v: float = float(explain(stat)["value"])
	_cache[stat] = v
	return v


## Desglose paso a paso del calculo (depurador / trazabilidad).
func explain(stat: String) -> Dictionary:
	var base: float = get_base(stat)
	var value: float = base
	var set_mod: StatModifier = null
	var flat := 0.0
	var pct := 0.0
	var mult := 1.0
	var has_floor := false
	var floor_v := 0.0
	var has_cap := false
	var cap_v := 0.0
	for m in _mods:
		if m.stat != stat:
			continue
		match m.kind:
			StatModifier.Kind.SET:
				if set_mod == null or m.priority > set_mod.priority or (m.priority == set_mod.priority and m.seq > set_mod.seq):
					set_mod = m
			StatModifier.Kind.FLAT:
				flat += m.value
			StatModifier.Kind.PCT_ADD:
				pct += m.value
			StatModifier.Kind.MULT:
				mult *= m.value
			StatModifier.Kind.MIN:
				floor_v = m.value if not has_floor else maxf(floor_v, m.value)
				has_floor = true
			StatModifier.Kind.MAX:
				cap_v = m.value if not has_cap else minf(cap_v, m.value)
				has_cap = true
	if set_mod != null:
		value = set_mod.value
	value = (value + flat) * (1.0 + pct) * mult
	if has_floor:
		value = maxf(value, floor_v)
	if has_cap:
		value = minf(value, cap_v)
	return {
		"stat": stat, "base": base, "set": set_mod.value if set_mod != null else null,
		"flat": flat, "pct_add": pct, "mult": mult,
		"floor": floor_v if has_floor else null, "cap": cap_v if has_cap else null,
		"value": value,
	}


## Mapa {stat: valor efectivo} de todas las estadisticas conocidas.
func effective_map() -> Dictionary:
	var out := {}
	for s in stat_ids():
		out[s] = get_value(s)
	return out


func duplicate_base() -> Dictionary:
	return _base.duplicate()
