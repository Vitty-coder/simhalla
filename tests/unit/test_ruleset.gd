extends TestCase
## Reglamento: valores por defecto, fusion, validacion y huella estable.


func test_defaults_valid() -> void:
	var r := Ruleset.from_dict({})
	assert_true(r.is_valid(), str(r.errors))
	assert_eq(r.threshold_micro(), 1_000_000_000)
	assert_eq(r.main_actions_per_turn(), 1)


func test_default_file_matches_default_data() -> void:
	var r := Ruleset.from_file("res://content/rulesets/default_ruleset.json")
	assert_true(r.is_valid(), str(r.errors))
	# JSON no distingue int/float: se normaliza ambos lados antes de comparar.
	var norm_file: Variant = JSON.parse_string(JSON.stringify(r.data, "", true))
	var norm_def: Variant = JSON.parse_string(JSON.stringify(Ruleset.default_data(), "", true))
	assert_eq(JSON.stringify(norm_file, "", true), JSON.stringify(norm_def, "", true), "el JSON por defecto refleja default_data()")


func test_merge_overrides_nested() -> void:
	var r := Ruleset.from_dict({"atb": {"initiative_threshold": 500.0}, "damage": {"rounding": {"decimals": 2}}})
	assert_true(r.is_valid(), str(r.errors))
	assert_eq(r.threshold_micro(), 500_000_000)
	assert_eq(r.rounding_decimals(), 2)
	assert_eq(r.rounding_mode(), "round", "lo no sobrescrito se conserva")


func test_validation_errors() -> void:
	var bad := [
		{"atb": {"initiative_threshold": 0.0}},
		{"atb": {"tie_break": ["nope"]}},
		{"atb": {"tie_break": []}},
		{"damage": {"rounding": {"mode": "weird"}}},
		{"damage": {"min_effective_defense": -100.0}},
		{"damage": {"min_elemental_resistance": 2.0}},
		{"damage": {"roll_scope": "x"}},
		{"hit": {"min_chance": 0.9, "max_chance": 0.1}},
		{"victory": {"limit_resolution": "x"}},
		{"victory": {"limits": {"max_turns": 0}}},
		{"basic_attack": {"formula": "1 +"}},
		{"safety": {"max_events": 0}},
	]
	for b in bad:
		assert_false(Ruleset.from_dict(b).is_valid(), "debe ser invalido: %s" % JSON.stringify(b))


func test_hard_caps_not_exceeded_by_content() -> void:
	var r := Ruleset.from_dict({"safety": {"max_events": 999_999_999, "max_event_depth": 9999}, "turn": {"max_actions_per_turn": 100000}})
	assert_eq(r.max_events(), Ruleset.HARD_MAX_EVENTS)
	assert_eq(r.max_event_depth(), Ruleset.HARD_MAX_EVENT_DEPTH)
	assert_eq(r.max_actions_per_turn(), Ruleset.HARD_MAX_ACTIONS_PER_TURN)


func test_content_hash_stable_and_sensitive() -> void:
	var a := Ruleset.from_dict({})
	var b := Ruleset.from_dict({})
	var c := Ruleset.from_dict({"atb": {"initiative_threshold": 999.0}})
	assert_eq(a.content_hash(), b.content_hash())
	assert_ne(a.content_hash(), c.content_hash())
	assert_eq(a.content_hash().length(), 64)


func test_rounding_modes() -> void:
	assert_almost(Rounding.apply(2.5, "round", 0), 3.0)
	assert_almost(Rounding.apply(-2.5, "round", 0), -3.0)
	assert_almost(Rounding.apply(2.9, "floor", 0), 2.0)
	assert_almost(Rounding.apply(2.1, "ceil", 0), 3.0)
	assert_almost(Rounding.apply(-2.9, "trunc", 0), -2.0)
	assert_almost(Rounding.apply(1.23456, "round", 2), 1.23)
	assert_almost(Rounding.apply(1.23456, "none", 2), 1.23456)
