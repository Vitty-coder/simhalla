class_name DamageCalculator
extends RefCounted
## Calculo puro de dano de un componente (sin azar ni efectos secundarios).
##
## Orden de resolucion (provisional, docs/COMBAT_RULES.md):
##   1. base (formula del componente; negativa -> 0)
##   2. critico: * CRIT_DMG del atacante (si el critico se decidio fuera)
##   3. afinidad elemental ofensiva: * (1 + ELEM_AFF.<elem>), minimo 0
##   4. mitigacion DEF/RES: * 100 / (100 + defensa_efectiva)   [verdadero: omitida]
##        defensa_efectiva = max(def * (1 - pen_pct) - pen_flat, min_effective_defense)
##   5. resistencia elemental defensiva: * (1 - res), res acotada por el reglamento
##        (res >= 1 = inmunidad; res < 0 = vulnerabilidad)
##   6. redondeo configurable; resultado >= 0
## Escudos, bloqueo, absorcion y demas defensas se aniaden en la fase 3 como
## fases adicionales de este mismo pipeline (por eventos DAMAGE_PRE).

## Devuelve un desglose: {"base","after_crit","premitigation","after_defense",
## "after_resistance","amount", "defense_used", "resistance_used", "steps":[...]}
static func compute(rules: Ruleset, attacker: CombatEntity, defender: CombatEntity, component: Dictionary, base_value: float, is_crit: bool) -> Dictionary:
	var steps: Array = []
	var damage_type: String = str(component.get("damage_type", "physical"))
	var element: String = str(component.get("element", ""))

	var value: float = base_value
	if value < 0.0:
		steps.append({"step": "negative_base_clamped", "from": value, "to": 0.0})
		value = 0.0
	var base: float = value

	if is_crit:
		var cm: float = maxf(attacker.stats.get_value("CRIT_DMG"), 0.0)
		value *= cm
		steps.append({"step": "crit", "multiplier": cm, "value": value})
	var after_crit: float = value

	if element != "":
		var aff: float = attacker.stats.get_value("ELEM_AFF." + element)
		var m: float = maxf(1.0 + aff, 0.0)
		value *= m
		steps.append({"step": "elemental_affinity", "element": element, "multiplier": m, "value": value})
	var premitigation: float = value

	var defense_used: float = 0.0
	if damage_type == "physical" or damage_type == "magical":
		var stat_id: String = "DEF" if damage_type == "physical" else "RES"
		var raw_def: float = defender.stats.get_value(stat_id)
		var pen_pct: float = clampf(float(component.get("pen_pct", 0.0)), 0.0, 1.0)
		var pen_flat: float = float(component.get("pen_flat", 0.0))
		var min_def: float = float(rules.get_path_value("damage.min_effective_defense"))
		defense_used = maxf(raw_def * (1.0 - pen_pct) - pen_flat, min_def)
		value = value * 100.0 / (100.0 + defense_used)
		steps.append({"step": "mitigation", "stat": stat_id, "raw": raw_def, "effective": defense_used, "value": value})
	var after_defense: float = value

	var res_used: float = 0.0
	if element != "":
		var res: float = defender.stats.get_value("ELEM_RES." + element)
		res -= float(component.get("elem_pen", 0.0))
		res = clampf(res, float(rules.get_path_value("damage.min_elemental_resistance")), float(rules.get_path_value("damage.max_elemental_resistance")))
		res_used = res
		value *= (1.0 - res)
		steps.append({"step": "elemental_resistance", "element": element, "resistance": res, "value": value})
	var after_resistance: float = value

	var amount: float = maxf(rules.round_value(value), 0.0)
	return {
		"base": base, "after_crit": after_crit, "premitigation": premitigation,
		"after_defense": after_defense, "after_resistance": after_resistance,
		"amount": amount, "defense_used": defense_used, "resistance_used": res_used,
		"steps": steps,
	}


## Probabilidad de impacto: ACC - EVA acotada por el reglamento.
static func hit_chance(rules: Ruleset, attacker: CombatEntity, defender: CombatEntity) -> float:
	var p: float = attacker.stats.get_value("ACC") - defender.stats.get_value("EVA")
	return clampf(p, float(rules.get_path_value("hit.min_chance")), float(rules.get_path_value("hit.max_chance")))


static func crit_chance(rules: Ruleset, attacker: CombatEntity) -> float:
	return clampf(attacker.stats.get_value("CRIT"), float(rules.get_path_value("hit.min_crit_chance")), float(rules.get_path_value("hit.max_crit_chance")))


## Curacion efectiva recibida (propuesta del PROJECT.md): raw * HEAL_REC.
static func heal_amount(rules: Ruleset, target: CombatEntity, raw: float) -> float:
	var rec: float = target.stats.get_value("HEAL_REC")
	return maxf(rules.round_value(maxf(raw, 0.0) * rec), 0.0)
