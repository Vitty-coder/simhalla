extends Phase3Case
## Fase 5: SimScript — lenguaje, limites, aislamiento, API de efectos, IA programada y paquetes.

const TMP := "user://_tests_phase5"


# --- utilidades --------------------------------------------------------------------------------------

func _compile(src: String, limits: ScriptLimits = null) -> Dictionary:
	return ScriptCompiler.compile(src, "t.sim", limits)


## Ejecuta `fn run(ctx)` de un script puro y devuelve {ok, value, error, instructions}.
func _eval(body: String, limits: ScriptLimits = null, extra: String = "") -> Dictionary:
	var c := _compile("%s\nfn run(ctx) { %s }" % [extra, body], limits)
	assert_eq(c["errors"], [], "compila: " + body)
	if c["program"] == null:
		return {"ok": false, "value": null, "error": "no compila", "instructions": 0}
	var it := ScriptInterpreter.new(c["program"], limits if limits != null else ScriptLimits.default_limits(), null, ScriptApi.EFFECT)
	return it.call_entry("run", [{"a": 1.0}])


func _val(body: String, extra: String = "") -> Variant:
	var r := _eval(body, null, extra)
	assert_true(r["ok"], "%s -> %s" % [body, str(r["error"])])
	return r["value"]


func _err_of(body: String, limits: ScriptLimits = null, extra: String = "") -> String:
	var r := _eval(body, limits, extra)
	assert_false(r["ok"], "debe fallar: " + body)
	return str(r["error"])


func _compile_errors(src: String, limits: ScriptLimits = null) -> String:
	var c := _compile(src, limits)
	assert_true(c["program"] == null and c["errors"].size() > 0, "debe rechazar: " + src.substr(0, 60))
	return " ".join(c["errors"])


func _dummy(id: String = "t", team: String = "B", extra: Dictionary = {}) -> CombatEntity:
	var d := {"stats": {"SPD": 1, "HP": 9000, "EVA": 0.0}}
	d.merge(extra, true)
	return ent(id, team, d)


## Entidad con una habilidad `zap` que ejecuta el script `s`.
func _caster(src: String, extra: Dictionary = {}, args: Dictionary = {}) -> CombatEntity:
	var d := {"stats": {"SPD": 100, "HP": 500, "MAG": 100, "ATK": 50}, "resources": {"mana": {"initial": 50, "min": 0, "max": 100}},
		"abilities": [{"id": "zap", "targeting": "enemy", "effects": [{"type": "script", "script": "s", "args": args}]}],
		"scripts": {"s": src}, "ai": {"type": "priority_list", "rules": [{"ability": "zap"}]}}
	d.merge(extra, true)
	return ent("a", "A", d)


func _cast(eng: CombatEngine, caster: CombatEntity, ability: String, target: CombatEntity) -> void:
	ActionResolver.resolve(eng, TurnState.new(caster, 1), caster, caster.get_ability(ability), [target] as Array[CombatEntity], 0)


func _build(data: Dictionary) -> Dictionary:
	var d := {"id": "x", "team": "A", "basic_attack": false}
	d.merge(data, true)
	return EntityFactory.build(d, BalanceProfile.default_profile(), Ruleset.from_dict({}), OperationRegistry.new())


# --- lenguaje ------------------------------------------------------------------------------------------

func test_language_arithmetic_strings_collections_and_control_flow() -> void:
	assert_almost(_val("return 2 + 3 * 4 - 10 / 4;"), 11.5)
	assert_almost(_val("return 7 % 4 + -2;"), 1.0)
	assert_eq(_val("return \"ab\" + \"cd\";"), "abcd")
	assert_eq(_val("return [1, 2] + [3];"), [1.0, 2.0, 3.0])
	assert_eq(_val("let m = {x: 1, \"y z\": 2}; m.x = 5; m[\"w\"] = 3; return m;"), {"x": 5.0, "y z": 2.0, "w": 3.0})
	assert_eq(_val("let l = [1, 2, 3]; l[1] = 9; push(l, 4); return l;"), [1.0, 9.0, 3.0, 4.0])
	assert_eq(_val("return 1 < 2 and 2 <= 2 and not (3 == 4) and 3 != 4 or false;"), true)
	assert_eq(_val("return \"a\" < \"b\";"), true)
	assert_eq(_val("if false { return 1; } else if 1 == 1 { return 2; } else { return 3; }"), 2.0)
	assert_almost(_val("let s = 0; for i in range(5) { s = s + i; } return s;"), 10.0)
	assert_almost(_val("let s = 0; for i in range(2, 5) { s = s + i; } return s;"), 9.0)
	assert_almost(_val("let s = 0; for v in [4, 5, 6] { if v == 5 { continue; } s = s + v; } return s;"), 10.0)
	assert_almost(_val("let n = 0; while true { n = n + 1; if n >= 7 { break; } } return n;"), 7.0)
	assert_almost(_val("return fact(5);", "fn fact(n) { if n <= 1 { return 1; } return n * fact(n - 1); }"), 120.0)
	assert_almost(_val("return K * 2;", "const K = 21;"), 42.0)
	# ambito de bloque: la variable del `if` no existe fuera
	assert_contains(_compile_errors("fn run(ctx) { if true { let z = 1; } return z; }"), "no declarada")
	# las colecciones se copian al guardarlas dentro de otras (sin ciclos posibles)
	assert_eq(_val("let a = [1]; let b = [a]; push(a, 2); return b;"), [[1.0]])
	assert_eq(_val("let a = {}; a.self = a; return a;"), {"self": {}})


func test_language_builtins() -> void:
	assert_almost(_val("return abs(-3) + floor(2.7) + ceil(2.1) + round(2.5) + sqrt(16) + min(1, 2) + max(1, 2) + clamp(9, 0, 5);"), 3.0 + 2.0 + 3.0 + 3.0 + 4.0 + 1.0 + 2.0 + 5.0)
	assert_almost(_val("return len([1, 2, 3]) + len(\"ab\") + len({a: 1});"), 6.0)
	assert_eq(_val("return str(3) + str(1.5) + str(true) + str(null);"), "31.5truenull")
	assert_almost(_val("return num(\"2.5\") + num(1);"), 3.5)
	assert_eq(_val("return keys({b: 1, a: 2});"), ["a", "b"])
	assert_eq(_val("return [has([1, 2], 2), has({a: 1}, \"a\"), has(\"abc\", \"bc\"), has([1], 5)];"), [true, true, true, false])
	assert_eq(_val("return sort([3, 1, 2]);"), [1.0, 2.0, 3.0])
	assert_almost(_val("return sum([1, 2, 3.5]);"), 6.5)
	assert_eq(_val("let l = [1, 2]; let x = pop(l); return [x, l];"), [2.0, [1.0]])
	assert_eq(_val("return [type(1), type(\"a\"), type(true), type(null), type([]), type({})];"), ["numero", "texto", "booleano", "null", "lista", "mapa"])
	assert_eq(_val("return ctx.a;"), 1.0)
	assert_eq(_val("return ctx.nope;"), null, "clave ausente de un mapa = null")


func test_runtime_errors_are_controlled_and_typed() -> void:
	assert_contains(_err_of("return 1 / 0;"), "division por cero")
	assert_contains(_err_of("return 1 % 0;"), "modulo por cero")
	assert_contains(_err_of("return 1 + \"a\";"), "no admite")
	assert_contains(_err_of("if 1 { }"), "booleana")
	assert_contains(_err_of("return not 1;"), "booleano")
	assert_contains(_err_of("return true and 1;"), "booleanos")
	assert_contains(_err_of("let l = [1]; return l[3];"), "fuera de rango")
	assert_contains(_err_of("let l = [1]; return l[0.5];"), "entero")
	assert_contains(_err_of("return 5[0];"), "indexar")
	assert_contains(_err_of("return sqrt(-1);"), "negativo")
	assert_contains(_err_of("return num(\"x\");"), "convertir")
	assert_contains(_err_of("return \"a\" < 1;"), "compara")
	assert_contains(_err_of("return 999999999999 * 999999999999;"), "fuera de rango")
	assert_contains(_err_of("return pop([]);"), "no vacia")
	assert_contains(_err_of("return sort([1, \"a\"]);"), "solo de numeros")
	assert_contains(_err_of("return keys(1);"), "mapa")
	# los errores incluyen script y linea
	assert_contains(_err_of("return 1 / 0;"), "t.sim:")


func test_static_validation_rejects_bad_programs_before_any_execution() -> void:
	var cases := {
		"variable no declarada": ["fn run(ctx) { return x; }", "no declarada"],
		"asignar sin declarar": ["fn run(ctx) { y = 1; }", "no declarada"],
		"funcion desconocida": ["fn run(ctx) { evil(); }", "no permitida o desconocida"],
		"aridad API": ["fn run(ctx) { hp(); }", "espera"],
		"aridad propia": ["fn f(a) { return a; } fn run(ctx) { f(1, 2); }", "espera 1"],
		"constante asignada": ["const K = 1; fn run(ctx) { K = 2; }", "constante"],
		"break suelto": ["fn run(ctx) { break; }", "fuera de un bucle"],
		"nombre reservado": ["fn while(ctx) { }", "se esperaba"],
		"funcion de API": ["fn hp(a) { return 1; } fn run(ctx) { }", "API"],
		"duplicada": ["fn f() { } fn f() { } fn run(ctx) { }", "ya esta definido"],
		"nivel superior": ["let x = 1;", "nivel superior"],
		"expresion suelta": ["fn run(ctx) { 1 + 2; }", "llamada"],
		"texto sin cerrar": ["fn run(ctx) { let s = \"abc; }", "sin cerrar"],
		"caracter": ["fn run(ctx) { let s = 1 @ 2; }", "caracter no permitido"],
		"escape": ["fn run(ctx) { let s = \"\\q\"; }", "escape"],
		"llamar a un valor": ["fn run(ctx) { let f = 1; f(); }", "no permitida o desconocida"],
		"constante no literal": ["const K = 1 + 2; fn run(ctx) { }", "literal"],
		"bloque suelto": ["fn run(ctx) { { } }", "bloque suelto"],
		"for range": ["fn run(ctx) { for i in range() { } }", "range"],
		"parametros": ["fn run(a, a) { }", "repetido"],
	}
	for k in cases:
		assert_contains(_compile_errors(cases[k][0]), cases[k][1], k)


func test_no_host_capabilities_reachable_from_scripts() -> void:
	# nada del anfitrion existe en el lenguaje: llamarlo es un error de compilacion (jamas se ejecuta)
	for fname in ["OS", "load", "preload", "FileAccess", "DirAccess", "print", "printerr", "eval", "call", "callv", "get_node", "get_tree", "Engine",
			"JavaClassWrapper", "ClassDB", "execute", "shell_open", "HTTPRequest", "Time", "randf", "randi", "rand_range", "instance_from_id", "set", "get", "free", "queue_free", "emit_signal"]:
		var c := _compile("fn run(ctx) { %s(\"x\"); }" % fname)
		assert_true(c["program"] == null, "debe rechazar %s" % fname)
		assert_contains(" ".join(c["errors"]), "no permitida")
	# acceso por miembro a "objetos": los valores son datos; no hay metodos ni reflexion
	assert_contains(_err_of("return ctx.a.x;"), "solo los mapas")
	assert_false(_compile("fn run(ctx) { ctx.a.free(); }")["program"] != null, "no hay llamadas a metodos")
	# solo datos cruzan la frontera: un objeto del motor no se puede convertir
	assert_false(ScriptValue.to_script(Object.new())["ok"])
	assert_false(ScriptValue.to_script({"a": RefCounted.new()})["ok"])
	assert_false(ScriptValue.to_script({1: 2})["ok"], "claves no textuales")
	assert_false(ScriptValue.to_script(Callable())["ok"])
	assert_true(ScriptValue.to_script({"a": [1, "x", true, null, 2.5]})["ok"])
	# los strings con codigo no se interpretan
	assert_eq(_val("return \"OS.execute(1)\";"), "OS.execute(1)")
	assert_contains(_compile_errors("fn run(ctx) { return \"x\".length(); }"), "se esperaba")


func test_resource_limits_instructions_depth_memory_and_size() -> void:
	assert_contains(_err_of("while true { }"), "presupuesto de 20000 instrucciones")
	assert_contains(_err_of("let i = 0; while i < 1000000 { i = i + 1; }"), "presupuesto")
	assert_contains(_err_of("for i in range(100000) { }"), "presupuesto")
	assert_contains(_err_of("return f(0);", null, "fn f(n) { return f(n + 1); }"), "profundidad")
	assert_contains(_err_of("let s = \"x\"; while true { s = s + s; }"), "texto demasiado largo")
	assert_contains(_err_of("let l = [1]; while true { push(l, 1); }"), "lista demasiado grande")
	assert_contains(_err_of("let l = [1]; while true { l = l + l; }"), "lista demasiado grande")
	assert_contains(_err_of("let m = {}; let i = 0; while true { m[str(i)] = 1; i = i + 1; }"), "mapa demasiado grande")
	var tiny := ScriptLimits.new()
	tiny.max_instructions = 50
	tiny.max_call_depth = 3
	assert_contains(_err_of("let s = 0; for i in range(100) { s = s + i; }", tiny), "presupuesto")
	assert_contains(_err_of("return f(0);", tiny, "fn f(n) { if n >= 10 { return n; } return f(n + 1); }"), "profundidad de llamadas maxima (3)")
	# deterministico: mismas instrucciones en cada ejecucion
	var a := _eval("let s = 0; for i in range(10) { s = s + i; } return s;")
	var b := _eval("let s = 0; for i in range(10) { s = s + i; } return s;")
	assert_eq(a["instructions"], b["instructions"])
	# tamano de entrada y complejidad de compilacion
	var big := "fn run(ctx) { }\n//" + "x".repeat(ScriptLimits.DEFAULTS["max_source_bytes"])
	assert_contains(_compile_errors(big), "tamano")
	var many := "fn run(ctx) { " + "let a=1;".repeat(1700) + "}"
	assert_contains(_compile_errors(many), "demasiado grande")
	assert_contains(_compile_errors("fn run(ctx) { return " + "(".repeat(100) + "1" + ")".repeat(100) + "; }"), "anidada")
	assert_contains(_compile_errors("fn run(ctx) { " + "if true { ".repeat(40) + "}".repeat(40) + " }"), "anidad")
	assert_contains(_compile_errors("fn run(ctx) { return \"" + "a".repeat(300) + "\"; }"), "texto literal demasiado largo")


func test_ruleset_scripting_limits_are_validated_and_applied() -> void:
	assert_true(Ruleset.from_dict({}).is_valid())
	assert_false(Ruleset.from_dict({"scripting": {"max_instructions": 0}}).is_valid())
	assert_false(Ruleset.from_dict({"scripting": {"max_instructions": 99999999}}).is_valid(), "techo duro")
	assert_false(Ruleset.from_dict({"scripting": {"max_call_depth": "x"}}).is_valid())
	var lim := ScriptLimits.from_ruleset(Ruleset.from_dict({"scripting": {"max_instructions": 40}}))
	assert_eq(lim.max_instructions, 40)
	assert_eq(lim.max_call_depth, 16, "los demas, por defecto")
	# el limite del reglamento se aplica de verdad en combate
	var a := _caster("fn run(ctx) { let i = 0; while i < 1000 { i = i + 1; } }")
	var eng := engine([a, _dummy()], 1, {"scripting": {"max_instructions": 100}})
	_cast(eng, a, "zap", eng.get_entity("t"))
	assert_true(eng.is_aborted())


# --- API de efectos en combate ---------------------------------------------------------------------------

func test_effect_script_deals_damage_through_the_engine_pipeline() -> void:
	var src := """
fn run(ctx) {
  for t in ctx.targets {
    deal_damage(t, 100 + stat(ctx.caster, "MAG") * ctx.args.k, {"damage_type": "physical", "element": "fire"});
  }
}
"""
	var a := _caster(src, {}, {"k": 0.5})
	var b := _dummy("t", "B", {"stats": {"SPD": 1, "HP": 1000, "DEF": 100, "ELEM_RES.fire": 0.5}})
	var eng := engine([a, b])
	_cast(eng, a, "zap", b)
	# base 150, afinidad 1 -> 150, mitigacion DEF 100 => *0.5 = 75, resistencia fuego 50% => 37.5 -> redondeo del reglamento: 38
	assert_almost(b.hp, 1000.0 - 38.0)
	var pre := events(eng, EventTypes.DAMAGE_PRE)
	var dealt := events(eng, EventTypes.DAMAGE_DEALT)
	assert_eq(pre.size(), 1, "pasa por damage_pre (interceptable)")
	assert_eq(dealt[0]["source"], "a")
	assert_almost(dealt[0]["data"]["amount"], 38.0)
	var run_ev := events(eng, EventTypes.SCRIPT_RUN)
	assert_eq(run_ev.size(), 1)
	assert_true(run_ev[0]["data"]["ok"])
	assert_eq(run_ev[0]["data"]["mutations"], 1)
	assert_true(int(run_ev[0]["data"]["instructions"]) > 0)
	check_causality(eng)


func test_effect_script_damage_can_be_intercepted_like_any_other() -> void:
	var a := _caster("fn run(ctx) { deal_damage(ctx.targets[0], 100, {\"damage_type\": \"true\"}); }")
	var b := _dummy("t", "B", {"stats": {"SPD": 1, "HP": 1000}})
	var eng := engine([a, b])
	eng.dispatcher.intercept(EventTypes.DAMAGE_PRE, func(ev: CombatEvent, _g: CombatEngine): ev.cancel("escudo_test", "bloqueado"), 0, "test")
	_cast(eng, a, "zap", b)
	assert_almost(b.hp, 1000.0, 1e-9, "el motor, no el script, decide")
	assert_eq(events(eng, EventTypes.DAMAGE_DEALT).size(), 0)


func test_effect_script_queries_heals_resources_status_events_metrics_and_vars() -> void:
	var src := """
fn run(ctx) {
  let me = ctx.caster;
  heal(me, 80);
  modify_resource(me, "mana", -10);
  apply_status(ctx.targets[0], "poison", {"stacks": 2, "duration": 3});
  emit("script_done", {"n": len(enemies(me)), "ratio": hp_ratio(me), "tag": has_tag(me, "mage")});
  metric("my_metric", res(me, "mana"));
  let n = get_var("casts");
  if n == null { n = 0; }
  set_var("casts", n + 1);
  return null;
}
"""
	var a := _caster(src, {"tags": ["mage"]})
	var b := _dummy("t", "B")
	var eng := engine([a, b])
	hit(eng, b, a, 200.0)
	_cast(eng, a, "zap", b)
	assert_almost(a.hp, 500.0 - 200.0 + 80.0)
	assert_almost((a.get_resource("mana") as ResourceState).value, 40.0)
	assert_eq(b.statuses.size(), 1)
	assert_eq(b.statuses[0].stacks, 2)
	var ue := events(eng, "user.script_done")
	assert_eq(ue.size(), 1)
	assert_eq(ue[0]["data"]["n"], 1.0)
	assert_eq(ue[0]["data"]["tag"], true)
	assert_almost(ue[0]["data"]["ratio"], 380.0 / 500.0)
	assert_almost(eng.custom_metrics["my_metric"]["total"], 40.0)
	_cast(eng, a, "zap", b)
	assert_eq(a.script_vars["casts"], 2.0, "las variables persisten durante el combate")
	assert_false(a.script_vars.has("otra"))


func test_script_vars_reset_between_battles_and_are_validated() -> void:
	var a := _caster("fn run(ctx) { set_var(\"k\", 1); }")
	a.script_vars["stale"] = 1
	var eng := engine([a, _dummy()])
	assert_false(a.script_vars.has("stale"), "no se heredan entre batallas")
	var bad := _caster("fn run(ctx) { set_var(\"Mal Nombre\", 1); }")
	var e2 := engine([bad, _dummy()])
	_cast(e2, bad, "zap", e2.get_entity("t"))
	assert_true(e2.is_aborted())
	var lots := _caster("fn run(ctx) { for i in range(70) { set_var(\"v\" + str(i), 1); } }")
	var e3 := engine([lots, _dummy()], 1, {"scripting": {"max_mutations": 500}})
	_cast(e3, lots, "zap", e3.get_entity("t"))
	assert_true(e3.is_aborted())
	assert_contains(e3.get_error()["message"], "demasiadas variables")


func test_script_rng_is_the_engine_stream_deterministic_and_separate() -> void:
	var src := "fn run(ctx) { let r = rand(); let k = rand_int(1000); let c = chance(0.5); set_var(\"last\", [r, k, c]); emit(\"rolled\", {\"k\": k}); }"
	var run := func(seed_value: int) -> Array:
		var a := _caster(src)
		var eng := engine([a, _dummy()], seed_value)
		_cast(eng, a, "zap", eng.get_entity("t"))
		return a.script_vars["last"]
	assert_eq(run.call(5), run.call(5), "misma semilla, mismas tiradas")
	assert_ne(run.call(5), run.call(6))
	# consumir el flujo "script" no altera los flujos de combate (hit, crit...)
	var plain_a := ent("a", "A", {"stats": {"SPD": 100, "ACC": 0.5}, "basic_attack": true, "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack"}]}})
	var scripted_a := ent("a", "A", {"stats": {"SPD": 100, "ACC": 0.5}, "basic_attack": true, "scripts": {"s": "fn run(ctx) { rand(); }"},
		"abilities": [{"id": "z", "targeting": "self", "action_type": "free", "uses_per_turn": 1, "effects": [{"type": "script", "script": "s"}]}],
		"ai": {"type": "priority_list", "rules": [{"ability": "z", "target": "self"}, {"ability": "basic_attack"}]}})
	var e1 := engine([plain_a, _dummy("t", "B", {"stats": {"SPD": 1, "HP": 99999, "EVA": 0.0}})], 3, {"victory": {"limits": {"max_turns": 6, "stagnation_turns": 99}}})
	var e2b := engine([scripted_a, _dummy("t", "B", {"stats": {"SPD": 1, "HP": 99999, "EVA": 0.0}})], 3, {"victory": {"limits": {"max_turns": 6, "stagnation_turns": 99}}})
	e1.run()
	e2b.run()
	var hits1 := events(e1, EventTypes.HIT).size() + events(e1, EventTypes.MISS).size()
	var seq1 := (events(e1, EventTypes.HIT) + events(e1, EventTypes.MISS)).map(func(x): return x["type"])
	var seq2 := (events(e2b, EventTypes.HIT) + events(e2b, EventTypes.MISS)).map(func(x): return x["type"])
	assert_true(hits1 > 0)
	assert_eq(seq1, seq2, "las tiradas de impacto no dependen de que el script consuma RNG")


func test_script_errors_abort_with_diagnostic_never_a_silent_result() -> void:
	var cases := {
		"entidad desconocida": ["fn run(ctx) { hp(\"fantasma\"); }", "entidad desconocida"],
		"cantidad negativa": ["fn run(ctx) { heal(ctx.caster, -5); }", "negativa"],
		"estado inexistente": ["fn run(ctx) { apply_status(ctx.caster, \"nada\", {}); }", "estado desconocido"],
		"opcion invalida": ["fn run(ctx) { deal_damage(ctx.targets[0], 1, {\"hax\": 1}); }", "opcion desconocida"],
		"elemento": ["fn run(ctx) { deal_damage(ctx.targets[0], 1, {\"element\": \"plasma\"}); }", "catalogo"],
		"tipo": ["fn run(ctx) { deal_damage(ctx.targets[0], 1, {\"damage_type\": \"magia\"}); }", "damage_type"],
		"nombre de evento": ["fn run(ctx) { emit(\"Malo\"); }", "identificador"],
		"dato de evento": ["fn run(ctx) { emit(\"ok\", {\"a\": [1]}); }", "numero, texto o booleano"],
		"bucle infinito": ["fn run(ctx) { while true { } }", "presupuesto"],
		"division": ["fn run(ctx) { let x = 1 / 0; }", "division por cero"],
		"stat": ["fn run(ctx) { stat(ctx.caster, \"MAGIA_OSCURA\"); }", "estadistica desconocida"],
	}
	for k in cases:
		var a := _caster(cases[k][0])
		var eng := engine([a, _dummy()])
		_cast(eng, a, "zap", eng.get_entity("t"))
		assert_true(eng.is_aborted(), k)
		assert_eq(eng.get_error()["code"], "script_error", k)
		assert_contains(eng.get_error()["message"], cases[k][1], k)
	# en un combate real: aborted (no victoria/empate) con diagnostico
	var a2 := _caster("fn run(ctx) { let x = 1 / 0; }")
	var res := engine([a2, _dummy()], 1).run()
	assert_true(res.is_aborted())
	assert_eq(res.error["code"], "script_error")
	assert_false(res.is_draw())


func test_mutation_budget_and_dead_targets() -> void:
	var a := _caster("fn run(ctx) { for i in range(40) { heal(ctx.caster, 1); } }")
	var eng := engine([a, _dummy()])
	_cast(eng, a, "zap", eng.get_entity("t"))
	assert_true(eng.is_aborted())
	assert_contains(eng.get_error()["message"], "demasiadas operaciones")
	# danar a un objetivo muerto no es un error: se omite con evento
	var a2 := _caster("fn run(ctx) { deal_damage(ctx.targets[0], 5, {\"damage_type\": \"true\"}); deal_damage(ctx.targets[0], 5, {\"damage_type\": \"true\"}); }")
	var weak := _dummy("t", "B", {"stats": {"SPD": 1, "HP": 5}})
	var e2 := engine([a2, weak, _dummy("u", "B")])
	_cast(e2, a2, "zap", weak)
	assert_false(e2.is_aborted())
	assert_false(weak.alive)
	assert_eq(events(e2, EventTypes.TARGET_SKIPPED).size(), 1)


func test_script_is_deterministic_and_traceable() -> void:
	var run := func() -> CombatEngine:
		var a := _caster("fn run(ctx) { deal_damage(ctx.targets[0], 10 + rand_int(20), {\"damage_type\": \"true\"}); }")
		var eng := engine([a, _dummy("t", "B", {"stats": {"SPD": 1, "HP": 400}})], 11, {"victory": {"limits": {"max_turns": 5, "stagnation_turns": 99}}})
		eng.run()
		return eng
	var e1: CombatEngine = run.call()
	var e2: CombatEngine = run.call()
	assert_eq(e1.result.log_hash, e2.result.log_hash)
	var started: Dictionary = events(e1, EventTypes.COMBAT_STARTED)[0]
	var info: Dictionary = started["data"]["entities"][0]
	assert_true(info.has("scripts") and info["scripts"].has("s") and info["scripts"]["s"].length() == 64, "huella del script en combat_started")
	var runs := events(e1, EventTypes.SCRIPT_RUN)
	assert_true(runs.size() >= 3)
	assert_true(runs[0]["data"]["ok"])
	# otro codigo => otra huella => otro combate
	var a3 := _caster("fn run(ctx) { deal_damage(ctx.targets[0], 11 + rand_int(20), {\"damage_type\": \"true\"}); }")
	var e3 := engine([a3, _dummy("t", "B", {"stats": {"SPD": 1, "HP": 400}})], 11, {"victory": {"limits": {"max_turns": 5, "stagnation_turns": 99}}})
	assert_ne(e3.run().log_hash, e1.result.log_hash)


# --- enlace y validacion al construir ----------------------------------------------------------------------

func test_entity_build_links_and_validates_scripts() -> void:
	var ok := _build({"scripts": {"s": "fn run(ctx) { }"}, "abilities": [{"id": "z", "targeting": "self", "effects": [{"type": "script", "script": "s"}]}]})
	assert_eq(ok["errors"], [])
	assert_contains(" ".join(ok["warnings"]), "no es evaluable", "los scripts se marcan como no evaluables (fase 6), sin inventar un precio")
	assert_contains(" ".join(_build({"abilities": [{"id": "z", "targeting": "self", "effects": [{"type": "script", "script": "fantasma"}]}]})["errors"]), "inexistente")
	assert_contains(" ".join(_build({"scripts": {"s": "fn run(ctx) { evil(); }"}})["errors"]), "no permitida o desconocida")
	assert_contains(" ".join(_build({"scripts": {"s": "fn otra(ctx) { }"}, "abilities": [{"id": "z", "targeting": "self", "effects": [{"type": "script", "script": "s"}]}]})["errors"]), "falta la funcion de entrada")
	assert_contains(" ".join(_build({"scripts": {"s": "fn run(a, b) { }"}, "abilities": [{"id": "z", "targeting": "self", "effects": [{"type": "script", "script": "s"}]}]})["errors"]), "1 parametro")
	assert_contains(" ".join(_build({"scripts": {"Mal-Nombre": "fn run(ctx) { }"}})["errors"]), "nombre invalido")
	assert_contains(" ".join(_build({"scripts": {"s": 5}})["errors"]), "debe ser texto")
	assert_contains(" ".join(_build({"scripts": [1]})["errors"]), "objeto")
	var unused := _build({"scripts": {"s": "fn run(ctx) { }"}})
	assert_eq(unused["errors"], [])
	assert_contains(" ".join(unused["warnings"]), "no se usa")
	# un script de IA no puede usarse como efecto y viceversa (contexto)
	var ai_script := "fn decide(view) { return {wait: true}; }"
	assert_contains(" ".join(_build({"scripts": {"s": ai_script}, "abilities": [{"id": "z", "targeting": "self", "effects": [{"type": "script", "script": "s"}]}]})["errors"]), "falta la funcion de entrada")
	assert_contains(" ".join(_build({"scripts": {"s": "fn run(ctx) { }"}, "ai": {"type": "script", "script": "s"}})["errors"]), "falta la funcion de entrada")
	# las llamadas no permitidas en el contexto se rechazan al enlazar
	assert_contains(" ".join(_build({"scripts": {"s": "fn decide(view) { deal_damage(\"a\", 1); return {wait: true}; }"}, "ai": {"type": "script", "script": "s"}})["errors"]), "no esta permitida en el contexto 'ai'")
	assert_contains(" ".join(_build({"scripts": {"s": "fn decide(view) { rand(); return {wait: true}; }"}, "ai": {"type": "script", "script": "s"}})["errors"]), "no esta permitida en el contexto 'ai'")
	assert_contains(" ".join(_build({"scripts": {"s": "fn run(ctx) { predict(1, 2, 3); }"}, "abilities": [{"id": "z", "targeting": "self", "effects": [{"type": "script", "script": "s"}]}]})["errors"]), "no esta permitida en el contexto 'effect'")
	# solo se valida lo alcanzable desde la entrada: una funcion ajena al contexto sin usar no estorba
	assert_eq(_build({"scripts": {"s": "fn aux() { rand(); } fn decide(view) { return {wait: true}; }"}, "ai": {"type": "script", "script": "s"}})["errors"], [])
	# efecto dentro de un estado propio
	var st := _build({"scripts": {"s": "fn run(ctx) { }"}, "statuses": [{"id": "x", "duration": 2, "on_apply": [{"type": "script", "script": "s"}]}]})
	assert_eq(st["errors"], [], str(st["errors"]))
	assert_contains(" ".join(_build({"statuses": [{"id": "x", "duration": 2, "on_apply": [{"type": "script", "script": "nada"}]}]})["errors"]), "inexistente")


func test_script_operation_validation() -> void:
	var reg := OperationRegistry.new()
	assert_true(reg.has_operation("script"))
	assert_eq(reg.validate_effect({"type": "script", "script": "ok_1"}), [])
	for bad in [{"type": "script"}, {"type": "script", "script": "Mal"}, {"type": "script", "script": "a", "args": 5}, {"type": "script", "script": "a", "x": 1},
			{"type": "script", "script": "a", "args": {"k": Object.new()}}]:
		assert_true(reg.validate_effect(bad).size() > 0, JSON.stringify(bad) if not (bad.get("args") is Dictionary and (bad["args"] as Dictionary).has("k")) else "args con objeto")


# --- IA programada ------------------------------------------------------------------------------------------

const AI_SRC := """
fn decide(view) {
  let best = null;
  let best_d = -1;
  for la in view.legal_actions {
    for t in la.targets {
      let p = predict(view, la.ability_id, t);
      if p.damage > best_d { best_d = p.damage; best = {ability: la.ability_id, target: t, reason: "mejor_dano"}; }
    }
  }
  if best == null { return {wait: true, reason: "nada"}; }
  best.remember = {incr: {decisiones: 1}};
  return best;
}
"""


func _ai_fighter(src: String, id: String = "a") -> CombatEntity:
	return ent(id, "A", {"stats": {"SPD": 100, "HP": 500}, "scripts": {"ai": src}, "ai": {"type": "script", "script": "ai"},
		"abilities": [dmg_ability("chip", "10"), dmg_ability("big", "90")]})


func test_script_ai_decides_with_the_limited_view_and_remembers() -> void:
	var a := _ai_fighter(AI_SRC)
	var eng := engine([a, _dummy("t", "B", {"stats": {"SPD": 1, "HP": 500}})], 1, {"victory": {"limits": {"max_turns": 3, "stagnation_turns": 99}}})
	eng.run()
	var sel := events(eng, EventTypes.ACTION_SELECTED).filter(func(e): return e["source"] == "a")
	assert_eq(sel.size(), 3)
	assert_eq(sel[0]["data"]["ability"], "big")
	assert_eq(sel[0]["data"]["reason"], "mejor_dano")
	assert_true(int(sel[0]["data"]["details"]["script"]["instructions"]) > 0)
	assert_almost(float(a.ai_memory["vars"]["decisiones"]), 3.0, 1e-9, "memory_ops aplicadas por el motor")
	assert_eq(events(eng, EventTypes.AI_FALLBACK).size(), 0)
	assert_eq(a.ai.ai_id(), "script:ai")


func test_script_ai_view_is_the_same_restricted_view() -> void:
	var probe := "fn decide(view) { return {wait: true, reason: str(keys(view.others[0]))}; }"
	var p := _ai_fighter(probe, "p")
	var e2 := engine([p, _dummy("t", "B", {"stats": {"SPD": 1, "HP": 5000, "DEF": 7771}})])
	var d2 := p.ai.decide(ViewBuilder.build(e2, p, TurnState.new(p, 1)))
	assert_false(d2.reason.contains("stats"))
	assert_false(d2.reason.contains("abilities"))
	assert_false(d2.reason.contains("memory"))


func test_script_ai_errors_fall_back_to_wait_without_aborting() -> void:
	var cases := {
		"error de ejecucion": "fn decide(view) { return 1 / 0; }",
		"bucle infinito": "fn decide(view) { while true { } }",
		"resultado no mapa": "fn decide(view) { return 5; }",
		"clave desconocida": "fn decide(view) { return {ability: \"chip\", target: \"t\", hax: 1}; }",
		"sin habilidad": "fn decide(view) { return {target: \"t\"}; }",
		"remember invalido": "fn decide(view) { return {ability: \"chip\", target: \"t\", remember: {set: {k: [1]}}}; }",
	}
	for k in cases:
		var a := _ai_fighter(cases[k])
		var eng := engine([a, _dummy("t", "B", {"stats": {"SPD": 1, "HP": 500}})], 1, {"victory": {"limits": {"max_turns": 2, "stagnation_turns": 99}}})
		var res := eng.run()
		assert_false(res.is_aborted(), "%s: un error de IA no aborta el combate" % k)
		var fb := events(eng, EventTypes.AI_FALLBACK)
		assert_true(fb.size() >= 1, k)
		assert_eq(fb[0]["data"]["policy"], "wait")
		assert_eq(events(eng, EventTypes.WAIT).size(), 2, "%s: espera" % k)
	var a2 := _ai_fighter("fn decide(view) { return 1 / 0; }")
	var e2 := engine([a2, _dummy()])
	e2.run()
	assert_contains(events(e2, EventTypes.AI_FALLBACK)[0]["data"]["reason"], "division por cero")


func test_script_ai_proposals_are_revalidated_by_the_engine() -> void:
	var a := _ai_fighter("fn decide(view) { return {ability: \"super_nuke\", target: \"t\"}; }")
	var eng := engine([a, _dummy()], 1, {"victory": {"limits": {"max_turns": 1, "stagnation_turns": 99}}})
	eng.run()
	assert_eq(events(eng, EventTypes.ACTION_REJECTED).size(), 1, "una habilidad que no se tiene no se ejecuta")
	assert_eq(events(eng, EventTypes.AI_FALLBACK).size(), 1)
	assert_eq(events(eng, EventTypes.DAMAGE_DEALT).size(), 0)


func test_script_ai_works_inside_state_machines_trees_and_overlay() -> void:
	var sc := {"type": "script", "script": "ai"}
	var sm := {"type": "state_machine", "initial": "s", "states": {"s": {"strategy": sc}}}
	var bt := {"type": "behavior_tree", "root": {"type": "strategy", "strategy": sc}}
	for cfg in [sm, bt]:
		var a := ent("a", "A", {"stats": {"SPD": 100}, "scripts": {"ai": AI_SRC}, "ai": cfg, "abilities": [dmg_ability("chip", "10"), dmg_ability("big", "90")]})
		var eng := engine([a, _dummy("t", "B", {"stats": {"SPD": 1, "HP": 500}})])
		var d := a.ai.decide(ViewBuilder.build(eng, a, TurnState.new(a, 1)))
		assert_eq(d.ability_id, "big", str(cfg["type"]))
	var missing := _build({"ai": {"type": "state_machine", "initial": "s", "states": {"s": {"strategy": {"type": "script", "script": "nope"}}}}})
	assert_contains(" ".join(missing["errors"]), "no existe en la entidad")
	assert_contains(" ".join(AIFactory.build({"type": "script"})["errors"]), "'script'")
	assert_contains(" ".join(AIFactory.build({"type": "script", "script": "ok", "x": 1})["errors"]), "propiedad desconocida")


func test_script_ai_cannot_mutate_the_combat_or_consume_rng() -> void:
	# la IA no tiene operaciones de combate: se rechaza al construir (nunca llega a ejecutarse)
	for call in ["heal(\"a\", 100)", "deal_damage(\"t\", 1)", "set_var(\"k\", 1)", "rand()", "chance(0.5)", "emit(\"x\")", "modify_resource(\"a\", \"mana\", 5)"]:
		var b := _build({"scripts": {"s": "fn decide(view) { %s; return {wait: true}; }" % call}, "ai": {"type": "script", "script": "s"}})
		assert_true(b["errors"].size() > 0, call)
	# mutar la propia copia de la vista no cambia el combate ni la siguiente decision
	var src := "fn decide(view) { view.self.hp = 99999; view.self.memory.vars.hack = 1; return {wait: true}; }"
	var a := _ai_fighter(src)
	var eng := engine([a, _dummy()])
	a.ai.decide(ViewBuilder.build(eng, a, TurnState.new(a, 1)))
	assert_almost(a.hp, 500.0)
	assert_false(a.ai_memory["vars"].has("hack"))


# --- paquetes ---------------------------------------------------------------------------------------------------

func _pkg_dir(files: Dictionary) -> String:
	var d := "%s/p%d" % [TMP, Time.get_ticks_usec()]
	for rel in files:
		var p: String = d.path_join(rel)
		DirAccess.make_dir_recursive_absolute(p.get_base_dir())
		var f := FileAccess.open(p, FileAccess.WRITE)
		if files[rel] is PackedByteArray:
			f.store_buffer(files[rel])
		else:
			f.store_string(files[rel])
		f.close()
	return d


func _char_files(scripts: Dictionary, extra: Dictionary = {}) -> Dictionary:
	var files := {
		"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": "t/scripted", "version": "1.0.0", "type": "character", "name": "S"}),
		"character.json": JSON.stringify({"schema": "simhalla.character/1", "name": "Scripted", "stats": {"HP": 600, "SPD": 100, "MAG": 120}, "basic_attack": true}),
		"abilities.json": JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [
			{"id": "zap", "name": "Zap", "targeting": "enemy", "effects": [{"type": "script", "script": "zap", "args": {"power": 4}}]}]}),
		"ai.json": JSON.stringify({"schema": "simhalla.ai/1", "ai": {"type": "priority_list", "rules": [{"ability": "zap"}]}}),
	}
	for k in scripts:
		files["scripts/%s.sim" % k] = scripts[k]
	files.merge(extra, true)
	return files


const ZAP := "fn run(ctx) { for t in ctx.targets { deal_damage(t, stat(ctx.caster, \"MAG\") * ctx.args.power, {\"damage_type\": \"true\"}); } }"


func _importer() -> PackageImporter:
	return PackageImporter.new(ContentLibrary.new("%s/lib%d" % [TMP, Time.get_ticks_usec()]))


func test_character_package_with_scripts_imports_and_fights() -> void:
	var lib := ContentLibrary.new("%s/lib%d" % [TMP, Time.get_ticks_usec()])
	var imp := PackageImporter.new(lib)
	var rep := imp.import_package(_pkg_dir(_char_files({"zap": ZAP})))
	assert_true(rep.ok(), "\n".join(rep.errors))
	var out := DuelRunner.run({"seed": 2, "library": lib.root, "entities": [
		{"package": "t/scripted", "overrides": {"team": "A"}}, {"package": "t/scripted", "overrides": {"id": "rival", "team": "B"}}]})
	assert_true(out["ok"], str(out["errors"]))
	var r: CombatResult = out["result"]
	assert_false(r.is_aborted(), str(r.error))
	var eng: CombatEngine = out["engine"]
	assert_true(eng.log.of_type(EventTypes.SCRIPT_RUN).size() > 0)
	assert_eq((eng.get_entity("t/scripted").scripts["zap"] as ScriptProgram).analysis["calls"], ["deal_damage", "stat"])
	var again: CombatResult = DuelRunner.run({"seed": 2, "library": lib.root, "entities": [
		{"package": "t/scripted", "overrides": {"team": "A"}}, {"package": "t/scripted", "overrides": {"id": "rival", "team": "B"}}]})["result"]
	assert_eq(r.log_hash, again.log_hash, "mismo paquete + semilla = mismo combate")
	ContentLibrary._remove_tree(TMP)


func test_importing_never_executes_scripts() -> void:
	# un script que abortaria o no terminaria jamas al ejecutarse se importa sin problemas: solo se compila
	var imp := _importer()
	var rep := imp.import_package(_pkg_dir(_char_files({"zap": "fn run(ctx) { while true { } } fn boom() { return 1 / 0; }"})))
	assert_true(rep.ok(), "\n".join(rep.errors))
	ContentLibrary._remove_tree(TMP)


func test_invalid_script_packages_are_rejected_with_clear_errors() -> void:
	var cases := {
		"sintaxis": [_char_files({"zap": "fn run(ctx) { let = ; }"}), "zap.sim:1"],
		"funcion prohibida": [_char_files({"zap": "fn run(ctx) { execute(\"rm\"); }"}), "no permitida"],
		"metodo del anfitrion": [_char_files({"zap": "fn run(ctx) { OS.execute(\"rm\"); }"}), "llamadas a metodos"],
		"falta entrada": [_char_files({"zap": "fn otra(ctx) { }"}), "falta la funcion de entrada"],
		"script inexistente": [_char_files({}), "inexistente"],
		"nombre invalido": [_char_files({"zap": ZAP, "Mal": ZAP}), "nombre no valido"],
		"extension": [_char_files({"zap": ZAP}, {"scripts/extra.gd": "extends Node"}), "nombre no valido"],
		"gdscript": [_char_files({"zap": ZAP}, {"scripts/malicioso.gdscript": "x"}), "nombre no valido"],
		"fuera de scripts": [_char_files({"zap": ZAP}, {"extra.sim": "fn run(ctx) {}"}), "archivo_desconocido"],
		"BOM": [_char_files({"zap": "\ufefffn run(ctx) { }"}), "BOM"],
		"UTF-8": [_char_files({"zap": ZAP}, {"scripts/malo.sim": PackedByteArray([0xFF, 0xFE, 0x41])}), "UTF-8"],
		"demasiado grande": [_char_files({"zap": "fn run(ctx) { }\n//" + "x".repeat(20000)}), "tamano"],
	}
	for k in cases:
		var rep := _importer().validate(_pkg_dir(cases[k][0]))
		assert_false(rep.ok(), "debe rechazar: %s" % k)
		assert_contains("\n".join(rep.errors), cases[k][1], k)
	# las bibliotecas (abilities/ai) no admiten scripts
	var lib_pkg := {"manifest.json": JSON.stringify({"schema": "simhalla.manifest/1", "id": "t/lib", "version": "1.0.0", "type": "abilities", "name": "L"}),
		"abilities.json": JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "targeting": "enemy", "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "1"}]}]}]}),
		"scripts/s.sim": "fn run(ctx) { }"}
	var rep2 := _importer().validate(_pkg_dir(lib_pkg))
	assert_false(rep2.ok())
	assert_contains("\n".join(rep2.errors), "solo se admiten en paquetes de personaje")
	ContentLibrary._remove_tree(TMP)


func test_script_content_changes_package_fingerprint() -> void:
	var imp := _importer()
	var r1 := imp.validate(_pkg_dir(_char_files({"zap": ZAP})))
	var r2 := imp.validate(_pkg_dir(_char_files({"zap": ZAP.replace("power", "power") + " // v2"})))
	assert_true(r1.ok() and r2.ok())
	assert_ne(r1.hash, r2.hash)
	ContentLibrary._remove_tree(TMP)


func test_scripting_schemas_in_public_schemas() -> void:
	var v := SchemaValidator.new()
	assert_eq(v.validate("abilities.schema.json", {"schema": "simhalla.abilities/1", "abilities": [{"id": "z", "targeting": "self", "effects": [{"type": "script", "script": "s", "args": {"a": 1}}]}]}), [])
	assert_true(v.validate("abilities.schema.json", {"schema": "simhalla.abilities/1", "abilities": [{"id": "z", "targeting": "self", "effects": [{"type": "script", "script": "Mal"}]}]}).size() > 0)
	assert_eq(v.validate("ai.schema.json", {"schema": "simhalla.ai/1", "ai": {"type": "script", "script": "mi_ia"}}), [])


# --- ejemplo: mecanicas nuevas sin tocar el motor -----------------------------------------------------------

func test_example_package_new_mechanics_and_ai_without_engine_changes() -> void:
	var lib := ContentLibrary.new("%s/lib%d" % [TMP, Time.get_ticks_usec()])
	var rep := PackageImporter.new(lib).import_package("res://content/packages/rune_caster")
	assert_true(rep.ok(), "\n".join(rep.errors))
	var cfg := {"seed": 8, "library": lib.root, "entities": [
		{"package": "examples/rune_caster", "overrides": {"id": "rune", "team": "A"}},
		{"path": "res://content/fixtures/entities/attacker_b.json", "overrides": {"id": "b1", "team": "B"}},
		{"path": "res://content/fixtures/entities/attacker_b.json", "overrides": {"id": "b2", "team": "B"}}]}
	var out := DuelRunner.run(cfg)
	assert_true(out["ok"], str(out["errors"]))
	var r: CombatResult = out["result"]
	assert_false(r.is_aborted(), str(r.error))
	var eng: CombatEngine = out["engine"]
	assert_eq(eng.log.of_type("user.chain_done")[0]["data"]["jumps"], 2.0, "salta a los dos enemigos")
	var sel := eng.log.of_type(EventTypes.ACTION_SELECTED).filter(func(e): return e["source"] == "rune")
	assert_eq(sel[0]["data"]["reason"], "varios_enemigos", "la IA programada reacciona al numero de enemigos")
	# cada salto hace menos dano que el anterior (misma accion, mismo origen)
	var first_cast := int(eng.log.of_type(EventTypes.SCRIPT_RUN)[0]["cause"])
	var chain := eng.log.of_type(EventTypes.DAMAGE_DEALT).filter(func(e): return e["source"] == "rune" and e["data"]["element"] == "lightning")
	assert_true(chain.size() >= 2)
	assert_true(float(chain[0]["data"]["intended"]) > float(chain[1]["data"]["intended"]))
	assert_true(first_cast > 0)
	assert_true(eng.custom_metrics.has("chain_jumps"))
	var again: CombatResult = DuelRunner.run(cfg)["result"]
	assert_eq(r.log_hash, again.log_hash, "reproducible")
	var info: Dictionary = eng.log.of_type(EventTypes.COMBAT_STARTED)[0]["data"]["entities"][0]
	assert_eq(info["scripts"].keys().size(), 3, "huellas de los tres scripts en la traza")
	ContentLibrary._remove_tree(TMP)
