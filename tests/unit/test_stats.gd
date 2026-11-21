extends TestCase
## StatSet: orden de modificadores, prioridades, expiracion y estadisticas personalizadas.


func _s() -> StatSet:
	var s := StatSet.new()
	s.set_base("ATK", 100.0)
	return s


func test_base_and_missing_stat() -> void:
	var s := _s()
	assert_almost(s.get_value("ATK"), 100.0)
	assert_almost(s.get_value("NOPE"), 0.0, 1e-12, "estadistica ausente vale 0")
	assert_false(s.has_stat("NOPE"))


func test_flat_pct_mult_order() -> void:
	var s := _s()
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.FLAT, 20.0))
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.PCT_ADD, 0.25))
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.PCT_ADD, 0.25))
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.MULT, 2.0))
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.MULT, 1.5))
	# (100 + 20) * (1 + 0.5) * 2 * 1.5 = 540
	assert_almost(s.get_value("ATK"), 540.0)


func test_set_priority_and_recency() -> void:
	var s := _s()
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.SET, 10.0, "a", 1))
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.SET, 50.0, "b", 5))
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.SET, 70.0, "c", 5)) # mismo prio, mas reciente
	assert_almost(s.get_value("ATK"), 70.0)
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.FLAT, 5.0))
	assert_almost(s.get_value("ATK"), 75.0, 1e-9, "SET sustituye la base y luego se aplican los demas")


func test_min_max_clamp_cap_wins() -> void:
	var s := _s()
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.FLAT, 500.0))
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.MAX, 300.0))
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.MIN, 400.0)) # conflicto: gana el techo
	assert_almost(s.get_value("ATK"), 300.0)
	var t := _s()
	t.add_modifier(StatModifier.make("ATK", StatModifier.Kind.FLAT, -90.0))
	t.add_modifier(StatModifier.make("ATK", StatModifier.Kind.MIN, 25.0))
	assert_almost(t.get_value("ATK"), 25.0, 1e-9, "suelo")


func test_remove_by_source_and_cache_invalidation() -> void:
	var s := _s()
	assert_almost(s.get_value("ATK"), 100.0) # cachea
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.FLAT, 50.0, "buff1"))
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.FLAT, 25.0, "buff1"))
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.FLAT, 10.0, "buff2"))
	assert_almost(s.get_value("ATK"), 185.0)
	assert_eq(s.remove_by_source("buff1"), 2)
	assert_almost(s.get_value("ATK"), 110.0)
	var m := s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.FLAT, 1.0, "x", 0, "mi_id"))
	assert_eq(m.id, "mi_id")
	assert_true(s.remove_modifier("mi_id"))
	assert_false(s.remove_modifier("mi_id"))


func test_custom_and_elemental_stats() -> void:
	var s := _s()
	s.set_base("corruption_power", 3.0)
	s.set_base("ELEM_AFF.fire", 0.2)
	assert_almost(s.get_value("corruption_power"), 3.0)
	assert_almost(s.get_value("ELEM_AFF.fire"), 0.2)
	assert_almost(s.get_value("ELEM_AFF.ice"), 0.0)
	assert_contains(s.stat_ids(), "corruption_power")


func test_explain_breakdown() -> void:
	var s := _s()
	s.add_modifier(StatModifier.make("ATK", StatModifier.Kind.FLAT, 20.0, "arma"))
	var ex := s.explain("ATK")
	assert_almost(ex["base"], 100.0)
	assert_almost(ex["flat"], 20.0)
	assert_almost(ex["value"], 120.0)
