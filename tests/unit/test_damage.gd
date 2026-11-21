extends TestCase
## Formulas de dano (PROJECT.md 5): mitigacion, tipos, criticos, elementos, penetracion.

var rules := Ruleset.from_dict({})


func _calc(att_stats: Dictionary, def_stats: Dictionary, comp: Dictionary, base: float, crit: bool = false, r: Ruleset = null) -> Dictionary:
	var a := make_entity("a", "A", att_stats)
	var d := make_entity("d", "B", def_stats)
	return DamageCalculator.compute(r if r != null else rules, a, d, comp, base, crit)


func test_physical_200_vs_def100_is_100() -> void:
	var c := _calc({}, {"DEF": 100}, {"damage_type": "physical"}, 200.0)
	assert_almost(c["amount"], 100.0, 1e-9, "criterio de aceptacion 19.1")


func test_magical_uses_res_not_def() -> void:
	var c := _calc({}, {"DEF": 0, "RES": 300}, {"damage_type": "magical"}, 200.0)
	assert_almost(c["amount"], 50.0)
	var p := _calc({}, {"DEF": 0, "RES": 300}, {"damage_type": "physical"}, 200.0)
	assert_almost(p["amount"], 200.0, 1e-9, "fisico ignora RES")


func test_true_damage_ignores_def_and_res() -> void:
	var c := _calc({}, {"DEF": 999, "RES": 999}, {"damage_type": "true"}, 200.0)
	assert_almost(c["amount"], 200.0)


func test_true_damage_still_subject_to_elemental_resistance() -> void:
	var c := _calc({}, {"DEF": 999, "ELEM_RES.fire": 0.5}, {"damage_type": "true", "element": "fire"}, 200.0)
	assert_almost(c["amount"], 100.0)


func test_crit_multiplier() -> void:
	var c := _calc({"CRIT_DMG": 2.0}, {"DEF": 0}, {"damage_type": "physical"}, 100.0, true)
	assert_almost(c["amount"], 200.0)
	var n := _calc({"CRIT_DMG": 2.0}, {"DEF": 0}, {"damage_type": "physical"}, 100.0, false)
	assert_almost(n["amount"], 100.0)


func test_crit_default_is_1_5() -> void:
	var c := _calc({}, {"DEF": 0}, {"damage_type": "physical"}, 100.0, true)
	assert_almost(c["amount"], 150.0)


func test_elemental_affinity_and_resistance() -> void:
	var exact := Ruleset.from_dict({"damage": {"rounding": {"mode": "none"}}})
	var c := _calc({"ELEM_AFF.fire": 0.5}, {"DEF": 0, "ELEM_RES.fire": 0.25}, {"damage_type": "physical", "element": "fire"}, 100.0, false, exact)
	assert_almost(c["amount"], 112.5, 1e-9, "100 * 1.5 * 0.75")
	var rounded := _calc({"ELEM_AFF.fire": 0.5}, {"DEF": 0, "ELEM_RES.fire": 0.25}, {"damage_type": "physical", "element": "fire"}, 100.0)
	assert_almost(rounded["amount"], 113.0, 1e-9, "redondeo por defecto: mitad lejos de cero")


func test_elemental_vulnerability_and_immunity() -> void:
	var v := _calc({}, {"DEF": 0, "ELEM_RES.ice": -0.5}, {"damage_type": "physical", "element": "ice"}, 100.0)
	assert_almost(v["amount"], 150.0, 1e-9, "vulnerabilidad")
	var i := _calc({}, {"DEF": 0, "ELEM_RES.ice": 1.0}, {"damage_type": "physical", "element": "ice"}, 100.0)
	assert_almost(i["amount"], 0.0, 1e-9, "inmunidad")
	var over := _calc({}, {"DEF": 0, "ELEM_RES.ice": 5.0}, {"damage_type": "physical", "element": "ice"}, 100.0)
	assert_almost(over["amount"], 0.0, 1e-9, "resistencia acotada al maximo (1.0)")


func test_no_element_ignores_elemental_stats() -> void:
	var c := _calc({"ELEM_AFF.fire": 1.0}, {"DEF": 0, "ELEM_RES.fire": 1.0}, {"damage_type": "physical"}, 100.0)
	assert_almost(c["amount"], 100.0)


func test_penetration_pct_then_flat() -> void:
	# DEF 200, 50 % pen => 100, -20 plano => 80  => 180 * 100/180 = 100
	var c := _calc({}, {"DEF": 200}, {"damage_type": "physical", "pen_pct": 0.5, "pen_flat": 20.0}, 180.0)
	assert_almost(c["defense_used"], 80.0)
	assert_almost(c["amount"], 100.0)


func test_negative_defense_clamped_by_ruleset() -> void:
	var c := _calc({}, {"DEF": -500}, {"damage_type": "physical"}, 100.0)
	assert_almost(c["defense_used"], 0.0)
	assert_almost(c["amount"], 100.0, 1e-9, "sin division por cero ni amplificacion infinita")
	var lenient := Ruleset.from_dict({"damage": {"min_effective_defense": -50.0}})
	var c2 := _calc({}, {"DEF": -500}, {"damage_type": "physical"}, 100.0, false, lenient)
	assert_almost(c2["defense_used"], -50.0)
	assert_almost(c2["amount"], 200.0)


func test_negative_base_clamped_to_zero() -> void:
	var c := _calc({}, {"DEF": 0}, {"damage_type": "physical"}, -50.0)
	assert_almost(c["amount"], 0.0)


func test_rounding_applied_to_final_amount() -> void:
	var c := _calc({}, {"DEF": 100}, {"damage_type": "physical"}, 101.0) # 50.5 -> round
	assert_almost(c["amount"], 51.0)
	var fine := Ruleset.from_dict({"damage": {"rounding": {"mode": "round", "decimals": 1}}})
	var c2 := _calc({}, {"DEF": 100}, {"damage_type": "physical"}, 101.0, false, fine)
	assert_almost(c2["amount"], 50.5)
	var fl := Ruleset.from_dict({"damage": {"rounding": {"mode": "floor", "decimals": 0}}})
	assert_almost(_calc({}, {"DEF": 100}, {"damage_type": "physical"}, 101.0, false, fl)["amount"], 50.0)


func test_diminishing_returns() -> void:
	# Cada +100 de DEF reduce menos: 50 %, 66,7 %, 75 % de mitigacion.
	var m1 := _calc({}, {"DEF": 100}, {"damage_type": "physical"}, 1000.0, false, Ruleset.from_dict({"damage": {"rounding": {"mode": "none"}}}))
	var m2 := _calc({}, {"DEF": 200}, {"damage_type": "physical"}, 1000.0, false, Ruleset.from_dict({"damage": {"rounding": {"mode": "none"}}}))
	var m3 := _calc({}, {"DEF": 300}, {"damage_type": "physical"}, 1000.0, false, Ruleset.from_dict({"damage": {"rounding": {"mode": "none"}}}))
	assert_almost(m1["amount"], 500.0, 1e-9)
	assert_almost(m2["amount"], 333.3333333333333, 1e-9)
	assert_almost(m3["amount"], 250.0, 1e-9)


func test_hit_chance_acc_minus_eva_clamped() -> void:
	var a := make_entity("a", "A", {"ACC": 1.0})
	var d := make_entity("d", "B", {"EVA": 0.1})
	assert_almost(DamageCalculator.hit_chance(rules, a, d), 0.9)
	var d2 := make_entity("d2", "B", {"EVA": 3.0})
	assert_almost(DamageCalculator.hit_chance(rules, a, d2), 0.0, 1e-12, "suelo 0")
	var a2 := make_entity("a2", "A", {"ACC": 2.0})
	assert_almost(DamageCalculator.hit_chance(rules, a2, d), 1.0, 1e-12, "techo 1")
	var clamped := Ruleset.from_dict({"hit": {"min_chance": 0.05, "max_chance": 0.95}})
	assert_almost(DamageCalculator.hit_chance(clamped, a2, d), 0.95)
	assert_almost(DamageCalculator.hit_chance(clamped, a, d2), 0.05)


func test_crit_chance_clamped() -> void:
	var a := make_entity("a", "A", {"CRIT": 1.7})
	assert_almost(DamageCalculator.crit_chance(rules, a), 1.0)


func test_heal_amount_uses_heal_rec() -> void:
	var t := make_entity("t", "A", {"HEAL_REC": 0.5})
	assert_almost(DamageCalculator.heal_amount(rules, t, 100.0), 50.0)
	var t2 := make_entity("t2", "A", {"HEAL_REC": 0.0})
	assert_almost(DamageCalculator.heal_amount(rules, t2, 100.0), 0.0, 1e-12, "curacion bloqueada")
	var t3 := make_entity("t3", "A", {"HEAL_REC": 2.0})
	assert_almost(DamageCalculator.heal_amount(rules, t3, 100.0), 200.0)


func test_defaults_from_balance_profile() -> void:
	var e := make_entity("e", "A")
	for pair in [["HP", 1000.0], ["ATK", 100.0], ["MAG", 100.0], ["DEF", 100.0], ["RES", 100.0], ["SPD", 100.0],
			["ACC", 1.0], ["EVA", 0.1], ["CRIT", 0.1], ["CRIT_DMG", 1.5], ["HEAL_REC", 1.0]]:
		assert_almost(e.stats.get_value(pair[0]), pair[1], 1e-12, "base %s" % pair[0])
