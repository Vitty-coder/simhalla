extends TestCase
## Formulas: gramatica segura, resolucion de variables, errores, limites.

func _ctx(vars: Dictionary) -> Callable:
	return func(parts: Array) -> Dictionary:
		var k := ".".join(parts)
		if vars.has(k):
			return {"ok": true, "value": float(vars[k]), "error": ""}
		return {"ok": false, "value": 0.0, "error": "desconocida %s" % k}


func _eval(text: String, vars: Dictionary = {}) -> Dictionary:
	return Formula.parse(text).evaluate(_ctx(vars))


func test_arithmetic_and_precedence() -> void:
	assert_almost(_eval("1 + 2 * 3")["value"], 7.0)
	assert_almost(_eval("(1 + 2) * 3")["value"], 9.0)
	assert_almost(_eval("10 / 4")["value"], 2.5)
	assert_almost(_eval("7 % 4")["value"], 3.0)
	assert_almost(_eval("-3 + 5")["value"], 2.0)
	assert_almost(_eval("2 ^ 3")["value"], 8.0)
	assert_almost(_eval("2 * 3 ^ 2")["value"], 18.0)
	assert_almost(_eval("2 ^ -1")["value"], 0.5)
	assert_almost(_eval("1.5 * 2")["value"], 3.0)
	assert_almost(_eval(".5 + .5")["value"], 1.0)


func test_variables() -> void:
	var r := _eval("caster.ATK * 1.5 + target.ELEM_RES.fire", {"caster.ATK": 100, "target.ELEM_RES.fire": 0.25})
	assert_true(r["ok"])
	assert_almost(r["value"], 150.25)


func test_functions() -> void:
	assert_almost(_eval("min(3, 1, 2)")["value"], 1.0)
	assert_almost(_eval("max(3, 1, 2)")["value"], 3.0)
	assert_almost(_eval("clamp(5, 0, 3)")["value"], 3.0)
	assert_almost(_eval("abs(-4)")["value"], 4.0)
	assert_almost(_eval("floor(2.9) + ceil(2.1) + round(2.5)")["value"], 8.0)
	assert_almost(_eval("sqrt(16)")["value"], 4.0)


func test_division_by_zero_is_error_not_inf() -> void:
	var r := _eval("1 / 0")
	assert_false(r["ok"])
	assert_contains(r["error"], "cero")
	assert_false(_eval("5 % 0")["ok"])


func test_unknown_variable_is_error() -> void:
	var r := _eval("caster.NOPE")
	assert_false(r["ok"])


func test_syntax_errors() -> void:
	for bad in ["", "   ", "1 +", "(1 + 2", "1 2", "foo(1)", "min()", "clamp(1,2)", "1..2", "3 $ 4", "a b"]:
		var f := Formula.parse(bad)
		assert_false(f.is_valid(), "deberia ser invalida: '%s'" % bad)


func test_no_host_code_execution() -> void:
	# Intentos de inyeccion: nunca se interpretan como codigo del anfitrion.
	for evil in ["OS.execute('ls')", "load('res://x')", "caster.ATK; print(1)", "get_node('/root')", "__import__('os')", "\"a\" + \"b\""]:
		var r := Formula.parse(evil).evaluate(_ctx({}))
		assert_false(r["ok"], "no debe evaluarse: %s" % evil)


func test_limits() -> void:
	assert_false(Formula.parse("1+".repeat(300) + "1").is_valid(), "demasiados nodos/longitud")
	assert_false(Formula.parse("(".repeat(100) + "1" + ")".repeat(100)).is_valid(), "demasiado anidada")
	assert_false(Formula.parse("1".repeat(600)).is_valid(), "demasiado larga")


func test_referenced_paths() -> void:
	var f := Formula.parse("caster.ATK * 2 + target.DEF - min(caster.hp, 5)")
	var p := f.referenced_paths()
	assert_contains(p, "caster.ATK")
	assert_contains(p, "target.DEF")
	assert_contains(p, "caster.hp")
	assert_eq(p.size(), 3)
