class_name Phase3Case
extends TestCase
## Utilidades compartidas por las pruebas de la fase 3.

const S := Ruleset.TIME_SCALE


func ent(id: String, team: String, data: Dictionary = {}, rules: Ruleset = null) -> CombatEntity:
	var d := {"id": id, "team": team, "basic_attack": false, "ai": {"type": "passive"}}
	d.merge(data, true)
	var rs := rules if rules != null else Ruleset.from_dict({})
	var b := EntityFactory.build(d, BalanceProfile.default_profile(), rs, OperationRegistry.new())
	assert_true(b["errors"].is_empty(), "%s: %s" % [id, str(b["errors"])])
	return b["entity"]


func engine(ents: Array, seed_value: int = 1, over: Dictionary = {}) -> CombatEngine:
	var r := {"victory": {"limits": {"max_turns": 12, "stagnation_turns": 99}}}
	r = Ruleset._merge(r, over)
	var eng := CombatEngine.new()
	var errs := eng.setup(Ruleset.from_dict(r), ents, seed_value)
	assert_eq(errs, [], "setup")
	return eng


func events(eng: CombatEngine, type: String) -> Array:
	return eng.log.of_type(type)


func dmg_ability(id: String, formula: String = "1", extra: Dictionary = {}) -> Dictionary:
	var d := {"id": id, "targeting": "enemy", "effects": [{"type": "damage", "always_hit": true, "can_crit": false,
		"components": [{"damage_type": "true", "formula": formula}]}]}
	d.merge(extra, true)
	return d


## Entrega dano directo (verdadero por defecto) a traves del pipeline completo.
func hit(eng: CombatEngine, from: CombatEntity, to: CombatEntity, amount: float, dtype: String = "true", element: String = "") -> void:
	eng.deliver_damage(from, to, {"component": 0, "damage_type": dtype, "element": element, "crit": false, "base": amount,
		"premitigation": amount, "defense_used": 0.0, "resistance_used": 0.0, "amount": amount}, 0)


## Comprueba invariantes de causalidad del registro completo.
func check_causality(eng: CombatEngine) -> void:
	var seen := {}
	var last := 0
	for ev in eng.log.events:
		assert_true(int(ev["id"]) > last, "ids monotonos")
		last = int(ev["id"])
		var c := int(ev["cause"])
		assert_true(c == 0 or seen.has(c), "causa existente y anterior: evento %s cause=%d" % [ev["type"], c])
		seen[int(ev["id"])] = true
