extends TestCase
## Validacion de datos de entidad: errores claros, nada se acepta a medias.

var rules := Ruleset.from_dict({})
var profile := BalanceProfile.default_profile()
var reg := OperationRegistry.new()


func _build(d: Dictionary) -> Dictionary:
	return EntityFactory.build(d, profile, rules, reg)


func _errs(d: Dictionary) -> String:
	return " | ".join(_build(d)["errors"])


func test_minimal_entity_gets_free_base_stats_and_basic_attack() -> void:
	var b := _build({"id": "x", "team": "A"})
	assert_true(b["errors"].is_empty(), str(b["errors"]))
	var e: CombatEntity = b["entity"]
	assert_almost(e.stats.get_value("HP"), 1000.0)
	assert_eq(e.abilities.size(), 1)
	assert_true(e.abilities[0].is_basic_attack)
	assert_true(e.ai is PriorityListAI, "IA por defecto: atacar con el ataque basico")
	assert_true(b["warnings"].size() > 0, "avisa de que los costes de creacion no se evaluan aun")


func test_stats_override_and_custom_stats() -> void:
	var e: CombatEntity = _build({"id": "x", "team": "A", "stats": {"ATK": 250, "fury_gain": 2.5, "ELEM_RES.fire": 0.3}})["entity"]
	assert_almost(e.stats.get_value("ATK"), 250.0)
	assert_almost(e.stats.get_value("fury_gain"), 2.5)
	assert_almost(e.stats.get_value("ELEM_RES.fire"), 0.3)
	assert_almost(e.stats.get_value("DEF"), 100.0, 1e-9, "lo no indicado conserva la base gratuita")


func test_rejects_bad_structure() -> void:
	assert_contains(_errs({"team": "A"}), "id")
	assert_contains(_errs({"id": "x", "stats": 5}), "stats")
	assert_contains(_errs({"id": "x", "stats": {"ATK": "mucho"}}), "ATK")
	assert_contains(_errs({"id": "x", "stats": {"HP": 0}}), "HP")
	assert_contains(_errs({"id": "x", "resources": {"mana": 5}}), "mana")
	assert_contains(_errs({"id": "x", "abilities": "no"}), "abilities")
	assert_contains(_errs({"id": "x", "abilities": [5]}), "objeto")


func test_ability_validation() -> void:
	var base := {"id": "x", "team": "A", "basic_attack": false}
	var cases := {
		"id": {"effects": []},
		"action_type": {"id": "a", "action_type": "turbo"},
		"targeting": {"id": "a", "targeting": "todos"},
		"target_count": {"id": "a", "target_count": 0},
		"coste negativo": {"id": "a", "cost": {"mana": -5}},
		"operacion desconocida": {"id": "a", "effects": [{"type": "teleport"}]},
		"components": {"id": "a", "effects": [{"type": "damage"}]},
		"damage_type": {"id": "a", "effects": [{"type": "damage", "components": [{"damage_type": "psiquico", "formula": "1"}]}]},
		"formula": {"id": "a", "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "1 +"}]}]},
		"origen de variable no permitido": {"id": "a", "effects": [{"type": "heal", "formula": "world.secret"}]},
		"sin 'type'": {"id": "a", "effects": [{}]},
	}
	for needle in cases:
		var d := base.duplicate(true)
		d["abilities"] = [cases[needle]]
		var msg := _errs(d)
		assert_contains(msg, needle, "caso '%s' -> %s" % [needle, msg])


func test_duplicate_ability_and_basic_attack_id_clash() -> void:
	var ab := {"id": "dup", "effects": []}
	assert_contains(_errs({"id": "x", "basic_attack": false, "abilities": [ab, ab]}), "duplicada")
	assert_contains(_errs({"id": "x", "abilities": [{"id": "basic_attack", "effects": []}]}), "duplicada")


func test_cost_requires_existing_resource() -> void:
	var ab := {"id": "a", "cost": {"mana": 5}, "effects": []}
	assert_contains(_errs({"id": "x", "basic_attack": false, "abilities": [ab]}), "recurso inexistente")
	assert_true(_build({"id": "x", "basic_attack": false, "resources": {"mana": {"initial": 5}}, "abilities": [ab]})["errors"].is_empty())


func test_ai_validation() -> void:
	assert_contains(_errs({"id": "x", "ai": {"type": "magic"}}), "tipo desconocido")
	assert_contains(_errs({"id": "x", "ai": {"type": "priority_list"}}), "rules")
	assert_contains(_errs({"id": "x", "ai": {"type": "priority_list", "rules": [{"ability": "nuke"}]}}), "inexistente")
	assert_contains(_errs({"id": "x", "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack", "target": "nadie"}]}}), "target")
	assert_contains(_errs({"id": "x", "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack", "when": {"self.hp": {"cerca": 1}}}]}}), "comparador")
	assert_contains(_errs({"id": "x", "ai": 5}), "objeto")


func test_fixture_files_all_valid() -> void:
	var dir := DirAccess.open("res://content/fixtures/entities")
	var n := 0
	for f in dir.get_files():
		if not f.ends_with(".json"):
			continue
		var d: Variant = EntityFactory.load_json("res://content/fixtures/entities/" + f)
		assert_true(d is Dictionary, f)
		var b := _build(d)
		assert_true(b["errors"].is_empty(), "%s: %s" % [f, str(b["errors"])])
		n += 1
	assert_true(n >= 6)


func test_balance_profile_validation() -> void:
	assert_false(BalanceProfile.from_dict({}).is_valid())
	assert_false(BalanceProfile.from_dict({"id": "p", "base_stats": {"HP": "x"}}).is_valid())
	assert_false(BalanceProfile.from_dict({"id": "p", "base_stats": {}}).is_valid())
	var p := BalanceProfile.from_file("res://content/balance/technical_profile.json")
	assert_true(p.is_valid(), str(p.errors))
	assert_true(p.illustrative, "el perfil tecnico esta marcado como ilustrativo")
