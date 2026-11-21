class_name PlatformCheck
extends RefCounted
## Diagnostico de plataforma (PROJECT.md §15 y fase 10): comprueba EN EL DISPOSITIVO que el motor produce los mismos resultados que
## la referencia (determinismo multiplataforma = objetivo tecnico, no promesa) y mide el rendimiento real.
##
## Baterias: informacion del dispositivo; vectores aritmeticos (operaciones IEEE, pow/sqrt/fmod, redondeos, conversiones texto<->float);
## secuencias del RNG propio; SHA-256/FNV; formulas; formato de numeros; 7 duelos de referencia (daño, estados, defensas, reacciones, scripts,
## IA puntuada/arbol/maquina, invocaciones, efectos retrasados, restaurar estado) cuyos `log_hash` se comparan con `content/conformance/expected.json`
## (generado por `tools/gen_conformance.gd` en la referencia); almacenamiento en user://; hilos; y bancos de rendimiento (no puntuan).
## Cualquier diferencia queda registrada como INCOMPATIBILIDAD con valor esperado y obtenido. Es incremental (`step()`) para no bloquear la UI.

const SCENARIOS := "res://content/conformance/scenarios.json"
const EXPECTED := "res://content/conformance/expected.json"
const TARGETS := "res://content/conformance/targets.json"
const VERSION := 1

var bench_ms: int = 1200
var info: Dictionary = {}
var checks: Array = [] ## [{name, ok, detail, expected, actual, kind: "check"|"info"}]
var perf: Array = [] ## [{scenario, duels, ms, duels_per_s, events_per_s, target, meets}]
var _tasks: Array = []
var _i: int = 0
var _expected: Dictionary = {}
var _scenarios: Dictionary = {}


func _init(options: Dictionary = {}) -> void:
	bench_ms = int(options.get("bench_ms", 1200))
	var e: Variant = EntityFactory.load_json(EXPECTED)
	_expected = e if e is Dictionary else {}
	var s: Variant = EntityFactory.load_json(SCENARIOS)
	_scenarios = s if s is Dictionary else {}
	_tasks = [["info", _t_info], ["math", _t_math], ["libm_info", _t_libm], ["rng", _t_rng], ["hashes", _t_hashes], ["formulas", _t_formulas], ["formats", _t_formats]]
	for sc in _scenarios.get("scenarios", []):
		var id := str(sc["id"])
		_tasks.append(["duel:" + id, func(): _t_duel(id)])
	_tasks.append_array([["examples", _t_examples], ["storage", _t_storage], ["flow", _t_flow], ["threads", _t_threads]])
	if not bool(options.get("skip_bench", false)):
		for id in ["simple", "effects", "summons"]:
			_tasks.append(["bench:" + id, func(): _t_bench(id)])


func total() -> int:
	return _tasks.size()


func done() -> int:
	return _i


func current_name() -> String:
	return str(_tasks[_i][0]) if _i < _tasks.size() else ""


## Ejecuta la siguiente tarea. Devuelve true mientras queden.
func step() -> bool:
	if _i >= _tasks.size():
		return false
	(_tasks[_i][1] as Callable).call()
	_i += 1
	return _i < _tasks.size()


func run_all() -> Dictionary:
	while step():
		pass
	return report()


func _add(name: String, ok: bool, detail: String = "", expected: Variant = null, actual: Variant = null, kind: String = "check") -> void:
	checks.append({"name": name, "ok": ok, "detail": detail, "expected": expected, "actual": actual, "kind": kind})


## expected vs actual (diccionarios nombre -> valor): una comprobacion por vector, agrupada en `name`.
func _compare(name: String, key: String, actual: Dictionary) -> void:
	var exp: Dictionary = _expected.get(key, {})
	if exp.is_empty():
		_add(name, false, "no hay valores esperados (`%s`): ejecute tools/gen_conformance.gd en la referencia" % key)
		return
	var bad: Array = []
	for k in exp:
		if not actual.has(k) or str(actual[k]) != str(exp[k]):
			bad.append({"vector": k, "expected": exp[k], "actual": actual.get(k, null)})
	for k in actual:
		if not exp.has(k):
			bad.append({"vector": k, "expected": null, "actual": actual[k]})
	_add(name, bad.is_empty(), "%d vectores" % actual.size() if bad.is_empty() else "%d de %d vectores difieren: %s" % [bad.size(), actual.size(), str(bad.slice(0, 3))], null if bad.is_empty() else bad)


# --- Vectores (tambien los usa tools/gen_conformance.gd para generar lo esperado) ------------------------------------------------

static func hex_of(v: float) -> String:
	var b := PackedByteArray()
	b.resize(8)
	b.encode_double(0, v)
	return b.hex_encode()


static func math_vectors() -> Dictionary:
	var out := {}
	var x := 0.1 + 0.2
	out["add"] = hex_of(x)
	out["div"] = hex_of(1.0 / 3.0)
	out["mul_chain"] = hex_of(100.0 / (100.0 + 37.0) * 123.456 * 1.5 - 0.25)
	out["sqrt2"] = hex_of(sqrt(2.0))
	out["sqrt_big"] = hex_of(sqrt(123456789.123))
	out["fmod"] = hex_of(fmod(10.7, 3.3))
	out["pow_half"] = hex_of(pow(2.0, 0.5))
	out["pow_int"] = hex_of(pow(1.1, 10.0))
	out["pow_neg"] = hex_of(pow(7.0, -0.3))
	out["pow_frac"] = hex_of(pow(3.0, 0.8))
	out["pow_cost"] = hex_of(pow(3.0, 0.8) * 0.35 * (0.5 + 0.5 * 0.4))
	out["floor"] = hex_of(floorf(-2.5))
	out["round_half"] = hex_of(roundf(2.5))
	out["round_neg"] = hex_of(roundf(-2.5))
	out["ceil"] = hex_of(ceilf(2.0000000001))
	out["clamp"] = hex_of(clampf(1.7, 0.0, 1.5))
	out["big_add"] = hex_of(1.0e15 + 0.5)
	out["tiny"] = hex_of(1.0e-300 * 1.0e-10)
	out["int_cast"] = hex_of(float(int(123456.99)))
	var acc := 0.0
	for i in 1000:
		acc += 1.0 / float(i + 1)
	out["harmonic_1000"] = hex_of(acc)
	var rnd := Rounding.apply(2.675, "round", 2)
	out["rounding_2dp"] = hex_of(rnd)
	out["time_scale"] = hex_of(float(Ruleset.TIME_SCALE) * 0.333)
	return out


## Funciones de libm que el motor NO usa: se informan, no puntuan.
static func libm_vectors() -> Dictionary:
	return {"exp1": hex_of(exp(1.0)), "log2": hex_of(log(2.0)), "sin1": hex_of(sin(1.0)), "cos1": hex_of(cos(1.0)), "tan1": hex_of(tan(1.0)), "atan2": hex_of(atan2(1.0, 2.0))}


static func rng_vectors() -> Dictionary:
	var r := Rng.new(123456789)
	var out := {}
	var ints: Array = []
	for i in 6:
		ints.append(str(r.next_int(1000000)))
	out["ints"] = ",".join(ints)
	var fl: Array = []
	for i in 4:
		fl.append(hex_of(r.next_float()))
	out["floats"] = ",".join(fl)
	out["state"] = str(r.state)
	out["mix"] = str(Rng.mix(0x1234567890ABCDEF))
	out["fnv"] = str(Rng.fnv1a64("simhalla"))
	var svc := RngService.new(-7046029254386353131)
	out["stream_hit"] = str(svc.stream("hit").next_int(1 << 30))
	out["stream_crit"] = hex_of(svc.stream("crit").next_float())
	return out


static func hash_vectors() -> Dictionary:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update("simhalla-conformance".to_utf8_buffer())
	var out := {"sha256": h.finish().hex_encode()}
	out["json_hash"] = VersionedStore.canonical_hash({"a": 1.5, "b": [1, 2, 3], "c": {"d": 0.1}})
	out["report_norm"] = JSON.stringify(ReportExporter._norm({"x": 0.9999999999999999, "y": 29.0, "z": 0.333333333333}), "", true, true)
	return out


static func formula_vectors() -> Dictionary:
	var out := {}
	var resolver := func(parts: Array) -> Dictionary:
		var key := ".".join(parts)
		var vals := {"caster.ATK": 137.0, "caster.MAG": 211.5, "target.DEF": 88.0, "caster.hp_ratio": 0.37}
		return {"ok": vals.has(key), "value": vals.get(key, 0.0), "error": "v"}
	for f in ["caster.ATK * 1.5 + 12", "caster.MAG ^ 0.75", "sqrt(caster.ATK) * 3.3 / (1 + target.DEF / 100)", "max(10, caster.ATK - target.DEF * 0.4) ^ 1.2", "clamp(caster.hp_ratio * 400, 50, 300) % 17", "abs(-caster.MAG) / 7"]:
		var r := Formula.parse(f).evaluate(resolver)
		out[f] = hex_of(float(r["value"])) if bool(r["ok"]) else "error:" + str(r["error"])
	return out


static func format_vectors() -> Dictionary:
	var out := {}
	for v in [0.1 + 0.2, 1.0 / 3.0, 123456.789012345678, 2.0 / 7.0 * 1000.0, 1.0e-7, 5.0e20]:
		out["str_%s" % hex_of(v)] = str(v)
		out["num6_%s" % hex_of(v)] = String.num(v, 6)
		out["f9_%s" % hex_of(v)] = "%.9f" % v
	out["parse"] = hex_of("0.1".to_float() + "2.675".to_float())
	out["json_full"] = JSON.stringify({"a": 1.0 / 3.0}, "", true, true)
	return out


# --- Tareas ---------------------------------------------------------------------------------------------------------------------

func _t_info() -> void:
	info = {"check_version": VERSION, "os": OS.get_name(), "model": OS.get_model_name(), "cpu": OS.get_processor_name(), "cpu_count": OS.get_processor_count(),
		"godot": Engine.get_version_info()["string"], "engine_version": CombatEngine.ENGINE_VERSION, "locale": OS.get_locale(), "display": DisplayServer.get_name(),
		"touchscreen": DisplayServer.is_touchscreen_available(), "mobile": OS.has_feature("mobile"), "debug_build": OS.is_debug_build(),
		"user_dir": OS.get_user_data_dir(), "rendering": str(ProjectSettings.get_setting("rendering/renderer/rendering_method", ""))}
	info["arch"] = Engine.get_architecture_name() if Engine.has_method("get_architecture_name") else "?"
	_add("info", true, "%s %s · %s · Godot %s" % [info["os"], info["arch"], info["model"], info["godot"]], null, null, "info")


func _t_math() -> void:
	_compare("math", "math", math_vectors())


func _t_libm() -> void:
	var exp: Dictionary = _expected.get("libm_extra", {})
	var act := libm_vectors()
	var diff := 0
	for k in exp:
		if str(act.get(k, "")) != str(exp[k]):
			diff += 1
	_add("libm_extra (informativo)", true, "%d de %d funciones difieren de la referencia (el motor no las usa)" % [diff, exp.size()], null, null, "info")


func _t_rng() -> void:
	_compare("rng", "rng", rng_vectors())


func _t_hashes() -> void:
	_compare("hashes", "hashes", hash_vectors())


func _t_formulas() -> void:
	_compare("formulas", "formulas", formula_vectors())


func _t_formats() -> void:
	_compare("formats", "formats", format_vectors())


func _scenario(id: String) -> Dictionary:
	for s in _scenarios.get("scenarios", []):
		if str(s["id"]) == id:
			return s
	return {}


func _duel_config(sc: Dictionary, trace: String = "reduced") -> Dictionary:
	return {"seed": int(sc["seed"]), "trace": trace, "ruleset_overrides": _scenarios.get("ruleset_overrides", {}), "entities": (sc["entities"] as Array).map(func(e): return {"data": e})}


## Resumen estable de un duelo: lo que se compara entre plataformas.
static func duel_summary(r: CombatResult) -> Dictionary:
	return {"log_hash": r.log_hash, "outcome": r.outcome, "reason": r.reason, "turns": r.turns, "events": r.events, "end_time": hex_of(r.end_time)}


func _t_duel(id: String) -> void:
	var sc := _scenario(id)
	var o := DuelRunner.run(_duel_config(sc))
	if not bool(o["ok"]):
		_add("duel:" + id, false, "no se pudo preparar: " + str(o["errors"]))
		return
	var r: CombatResult = o["result"]
	if r.is_aborted():
		_add("duel:" + id, false, "aborto tecnico: " + str(r.error))
		return
	var act := duel_summary(r)
	var exp: Dictionary = (_expected.get("duels", {}) as Dictionary).get(id, {})
	if exp.is_empty():
		_add("duel:" + id, false, "sin valor esperado (regenere con tools/gen_conformance.gd)")
	elif str(_expected.get("engine_version", "")) != CombatEngine.ENGINE_VERSION:
		_add("duel:" + id, false, "esperado generado con el motor %s (actual %s): regenere" % [str(_expected.get("engine_version", "?")), CombatEngine.ENGINE_VERSION])
	else:
		var same := JSON.stringify(ReportExporter._norm(act), "", true, true) == JSON.stringify(ReportExporter._norm(exp), "", true, true)
		_add("duel:" + id, same, "%s · %d turnos · %d eventos · %s" % [r.outcome, r.turns, r.events, r.log_hash.substr(0, 12)] if same else "INCOMPATIBLE: esperado %s, obtenido %s" % [str(exp.get("log_hash", "")).substr(0, 12), r.log_hash.substr(0, 12)], exp, act)


## Huellas de contenido de los paquetes de ejemplo leidos desde `res://` (en Android, desde el APK): valida la lectura de carpetas del
## recurso empaquetado, la importacion completa y que los bytes son identicos a los de la referencia.
static func example_hashes() -> Dictionary:
	var dir := "user://_platform_check/examples_lib"
	ContentLibrary._remove_tree("user://_platform_check/examples_lib")
	var lib := ContentLibrary.new(dir)
	var out := {}
	for n in AppController.EXAMPLES:
		var rep := PackageImporter.new(lib).import_package("res://content/packages/" + n)
		out[n] = rep.hash if rep.ok() else "error: " + "; ".join(rep.errors).substr(0, 120)
	ContentLibrary._remove_tree("user://_platform_check/examples_lib")
	return out


func _t_examples() -> void:
	_compare("examples", "examples", example_hashes())


## Flujo de aplicacion de extremo a extremo EN ESTE dispositivo (sin interfaz): ejemplos -> duelo -> guardar -> reproducir -> informe ->
## verificar -> bundle portable -> importar en otra instalacion. Falla con el primer paso que no funcione.
func _t_flow() -> void:
	var dir := "user://_platform_check/flow"
	ContentLibrary._remove_tree(dir)
	var step := "arranque"
	var err := ""
	var app := AppController.new(dir.path_join("a"))
	var boot := app.boot()
	if not boot.is_empty():
		err = "; ".join(boot)
	if err == "":
		step = "ejemplos"
		var ex := app.install_examples()
		if not (ex["errors"] as Array).is_empty():
			err = "; ".join(ex["errors"])
	var vm: ViewerModel = null
	if err == "":
		step = "duelo"
		app.duel.reset()
		app.duel.add_package("examples/arcane_duelist")
		app.duel.add_package("examples/iron_vanguard")
		var v := app.duel.validate()
		if not bool(v["can_start"]):
			err = str(v["errors"])
		else:
			var st := app.duel.start()
			if not bool(st.get("ok", false)) or st.get("viewer", null) == null:
				err = str(st.get("errors", "no se pudo iniciar"))
			else:
				vm = st["viewer"]
				vm.to_end()
	var bid := ""
	if err == "":
		step = "guardar"
		var sv := vm.save("flujo", false)
		if not bool(sv["ok"]):
			err = str(sv.get("error", sv))
		else:
			bid = str(sv["id"])
	if err == "":
		step = "reproducir"
		var rp := app.storage.replay_battle(bid)
		if not bool(rp["ok"]) or not bool(rp["matches"]):
			err = "la reproduccion no coincide: %s" % str(rp.get("errors", ""))
	if err == "":
		step = "informe"
		var rep := vm.save_report(bid)
		if not bool(rep["ok"]):
			err = str(rep.get("error", rep))
		else:
			var verr := app.reports.verify(str(rep["id"]))
			if not verr.is_empty():
				err = "informe no verificable: %s" % str(verr[0])
	if err == "":
		step = "bundle"
		var bp := dir.path_join("flow.simbundle")
		var ex2 := BundleIO.export_records(app.storage, [{"store": "battles", "id": bid}], bp)
		if not bool(ex2["ok"]):
			err = "; ".join(ex2["errors"])
		else:
			var other := AppController.new(dir.path_join("b"))
			other.boot()
			var im := BundleIO.import_bundle(other.storage, bp)
			if not bool(im["ok"]) or other.storage.battles.list().size() != 1:
				err = "importacion del bundle: %s" % str(im.get("errors", ""))
			else:
				var rp2 := other.storage.replay_battle(str((im["records"] as Array)[0]["new_id"]))
				if not bool(rp2["matches"]):
					err = "el combate importado no se reproduce igual"
	ContentLibrary._remove_tree(dir)
	_add("flow", err == "", "ejemplos, duelo, guardado, reproduccion, informe, bundle e importacion" if err == "" else "FALLA en '%s': %s" % [step, err])


func _t_storage() -> void:
	var dir := "user://_platform_check"
	DirAccess.make_dir_recursive_absolute(dir)
	var p := dir.path_join("t.json")
	var data := {"a": 1, "b": "texto ñ ✓", "c": [1.5, 2]}
	var f := FileAccess.open(p, FileAccess.WRITE)
	if f == null:
		_add("storage", false, "no se puede escribir en user://")
		return
	f.store_string(JSON.stringify(data))
	f.close()
	var back: Variant = JSON.parse_string(FileAccess.get_file_as_string(p))
	var ok: bool = back is Dictionary and str(back.get("b", "")) == "texto ñ ✓"
	var st := AppStorage.new(dir.path_join("store"))
	var r := st.rulesets.put("t/x", "1.0.0", {"damage": {"rounding": {"mode": "round", "decimals": 0}}})
	ok = ok and bool(r["ok"]) and bool(st.rulesets.get_item("t/x", "1.0.0")["ok"])
	ContentLibrary._remove_tree(dir)
	_add("storage", ok, "lectura/escritura y almacen versionado en user:// (%s)" % OS.get_user_data_dir() if ok else "fallo de lectura/escritura en user://")


func _t_threads() -> void:
	var sc := _scenario("simple")
	var spec_a: Dictionary = {"data": sc["entities"][0]}
	var spec_b: Dictionary = {"data": sc["entities"][1]}
	var cfg := BatchModes.duel(spec_a, spec_b, 6, 5, {"ruleset_overrides": _scenarios.get("ruleset_overrides", {})})
	var plan: BatchPlan = BatchPlan.from_dict(cfg)["plan"]
	var a := BatchRunner.new(plan, {"workers": 0}).wait()
	var b := BatchRunner.new(plan, {"workers": 2}).wait()
	_add("threads", a.fingerprint == b.fingerprint and b.executed == 6, "lote de 6 duelos: sincrono == 2 hilos (%s)" % a.fingerprint.substr(0, 12) if a.fingerprint == b.fingerprint else "INCOMPATIBLE: sincrono %s, hilos %s" % [a.fingerprint.substr(0, 12), b.fingerprint.substr(0, 12)])


## Clase de dispositivo para los objetivos de rendimiento: "mobile" (Android/iOS) o "desktop".
static func device_class() -> String:
	return "mobile" if OS.has_feature("mobile") else "desktop"


## Objetivo provisional de duelos/s del escenario para la clase de dispositivo (0.0 si no hay).
static func target_for(scenario: String, klass: String = "") -> float:
	var t: Variant = EntityFactory.load_json(TARGETS)
	if not (t is Dictionary):
		return 0.0
	var cls: Dictionary = (t.get("classes", {}) as Dictionary).get(klass if klass != "" else device_class(), {})
	return float(cls.get(scenario, 0.0))


func _t_bench(id: String) -> void:
	var sc := _scenario(id)
	var cfg := _duel_config(sc)
	var t0 := Time.get_ticks_msec()
	var n := 0
	var events := 0
	var s := 0
	while Time.get_ticks_msec() - t0 < bench_ms or n < 2:
		cfg["seed"] = int(sc["seed"]) + s
		s += 1
		var o := DuelRunner.run(cfg)
		if not bool(o["ok"]):
			break
		events += (o["result"] as CombatResult).events
		n += 1
	var ms := maxi(Time.get_ticks_msec() - t0, 1)
	var dps := float(n) * 1000.0 / float(ms)
	var target := PlatformCheck.target_for(id)
	perf.append({"scenario": id, "duels": n, "ms": ms, "duels_per_s": dps, "events_per_s": float(events) * 1000.0 / float(ms),
		"target": target, "meets": target <= 0.0 or dps >= target})


# --- Informe ------------------------------------------------------------------------------------------------------------------------

func passed() -> int:
	return checks.filter(func(c): return c["kind"] == "check" and bool(c["ok"])).size()


func failed() -> int:
	return checks.filter(func(c): return c["kind"] == "check" and not bool(c["ok"])).size()


func report() -> Dictionary:
	return {"schema": "simhalla.platform_check/1", "info": info, "summary": {"passed": passed(), "failed": failed(), "compatible": failed() == 0},
		"checks": checks, "perf": perf, "note": "determinismo multiplataforma = objetivo tecnico: cualquier diferencia queda registrada como incompatibilidad"}


func to_markdown() -> String:
	var s := "# Diagnostico de plataforma\n\n"
	s += "| Campo | Valor |\n|---|---|\n"
	for k in info:
		s += "| %s | %s |\n" % [MarkdownRenderer.esc(k), MarkdownRenderer.esc(info[k])]
	s += "\n**Resultado: %d correctas, %d fallidas — %s**\n\n| Comprobacion | Estado | Detalle |\n|---|---|---|\n" % [passed(), failed(), "COMPATIBLE con la referencia" if failed() == 0 else "INCOMPATIBILIDADES"]
	for c in checks:
		s += "| %s | %s | %s |\n" % [MarkdownRenderer.esc(c["name"]), "info" if c["kind"] == "info" else ("OK" if bool(c["ok"]) else "FALLO"), MarkdownRenderer.esc(c["detail"])]
	if not perf.is_empty():
		s += "\nObjetivos PROVISIONALES de rendimiento (clase %s; informativos, no puntuan).\n\n| Rendimiento | Duelos | ms | Duelos/s | Eventos/s | Objetivo | Cumple |\n|---|---:|---:|---:|---:|---:|---|\n" % device_class()
		for p in perf:
			s += "| %s | %d | %d | %.1f | %.0f | %.1f | %s |\n" % [p["scenario"], p["duels"], p["ms"], p["duels_per_s"], p["events_per_s"], p["target"], "si" if bool(p["meets"]) else "NO"]
	return s
