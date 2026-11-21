class_name BatchPlan
extends RefCounted
## Plan de un lote de simulaciones: escenarios x repeticiones -> trabajos con semilla DERIVADA de la maestra.
##
## La semilla de un trabajo depende solo de (semilla maestra, clave de escenario, repeticion) — o, en modo
## `paired`, de (semilla maestra, repeticion) para comparar variantes con los mismos azares — y NUNCA del orden de
## ejecucion, del numero de workers ni de la posicion en el plan. Ver `BatchModes` para los constructores de
## modalidades (duelo, torneo, biblioteca de adversarios, versiones, IA, reglamentos, variacion de parametros).
##
## Formato (JSON): {"schema":"simhalla.batch/1","name","master_seed","repetitions","seed_mode":"per_scenario|paired",
##   "base":{ruleset,profile,library,...},   <- fragmentos de DuelRunner comunes a todos los escenarios
##   "scenarios":[{"key","label","entities":[spec,spec,...],"sides":{"A":etiqueta,"B":etiqueta},"params":{},
##                 "ruleset_overrides":{},"initial_overrides":{},"repetitions":n?}]}

const SCHEMA := "simhalla.batch/1"
const MAX_JOBS := 1000000
const MAX_SCENARIOS := 10000
const SEED_MODES := ["per_scenario", "paired"]

var name: String = "batch"
var master_seed: int = 1
var repetitions: int = 1
var seed_mode: String = "per_scenario"
var base: Dictionary = {}
var scenarios: Array = []
var jobs: Array = [] ## [{index, scenario, repetition, seed}] en orden canonico (escenario, repeticion)


## {"plan": BatchPlan|null, "errors": Array}.
static func from_dict(cfg: Dictionary) -> Dictionary:
	var errs: Array = []
	var p := BatchPlan.new()
	for k in cfg:
		if not ["schema", "name", "master_seed", "repetitions", "seed_mode", "base", "scenarios"].has(str(k)):
			errs.append("lote: propiedad desconocida '%s'" % str(k))
	if cfg.has("schema") and str(cfg["schema"]) != SCHEMA:
		errs.append("lote: schema debe ser '%s'" % SCHEMA)
	p.name = str(cfg.get("name", "batch"))
	var ms: Variant = cfg.get("master_seed", 1)
	if not (ms is int or ms is float or (ms is String and (ms as String).is_valid_int())):
		errs.append("lote: master_seed debe ser un entero (o su texto: las semillas de 64 bits se guardan como texto)")
	p.master_seed = int(str(ms)) if ms is String else int(ms)
	p.repetitions = int(cfg.get("repetitions", 1))
	if p.repetitions < 1:
		errs.append("lote: repetitions debe ser >= 1")
	p.seed_mode = str(cfg.get("seed_mode", "per_scenario"))
	if not SEED_MODES.has(p.seed_mode):
		errs.append("lote: seed_mode desconocido '%s' (use: %s)" % [p.seed_mode, ", ".join(SEED_MODES)])
	if cfg.has("base") and not (cfg["base"] is Dictionary):
		errs.append("lote: 'base' debe ser un objeto")
	p.base = (cfg.get("base", {}) as Dictionary).duplicate(true) if cfg.get("base", {}) is Dictionary else {}
	for k in p.base:
		if not ["ruleset", "profile", "library", "ruleset_overrides", "initial_overrides", "balance", "ruleset_data", "profile_data"].has(str(k)):
			errs.append("lote.base: propiedad desconocida '%s'" % str(k))
	var sc: Variant = cfg.get("scenarios", null)
	if not (sc is Array) or (sc as Array).is_empty():
		errs.append("lote: 'scenarios' debe ser una lista no vacia")
		return {"plan": null, "errors": errs}
	if (sc as Array).size() > MAX_SCENARIOS:
		errs.append("lote: maximo %d escenarios" % MAX_SCENARIOS)
		return {"plan": null, "errors": errs}
	var seen := {}
	for i in (sc as Array).size():
		var s: Variant = sc[i]
		var w := "lote.scenarios[%d]" % i
		if not (s is Dictionary):
			errs.append("%s: debe ser un objeto" % w)
			continue
		for k in s:
			if not ["key", "label", "entities", "sides", "params", "ruleset_overrides", "initial_overrides", "repetitions", "group"].has(str(k)):
				errs.append("%s: propiedad desconocida '%s'" % [w, str(k)])
		var key := str(s.get("key", ""))
		if key == "" or seen.has(key):
			errs.append("%s: 'key' obligatoria y unica ('%s')" % [w, key])
		seen[key] = true
		var ents: Variant = s.get("entities", null)
		if not (ents is Array) or (ents as Array).size() < 2:
			errs.append("%s: 'entities' requiere al menos 2 entidades" % w)
		else:
			for j in (ents as Array).size():
				var e: Variant = ents[j]
				if not (e is Dictionary) or not (e.has("path") or e.has("package") or e.has("data")):
					errs.append("%s.entities[%d]: requiere 'path', 'package' o 'data'" % [w, j])
		if s.has("repetitions") and int(s["repetitions"]) < 1:
			errs.append("%s: repetitions debe ser >= 1" % w)
		p.scenarios.append((s as Dictionary).duplicate(true))
	if not errs.is_empty():
		return {"plan": null, "errors": errs}
	var total := 0
	for s in p.scenarios:
		total += int(s.get("repetitions", p.repetitions))
	if total > MAX_JOBS:
		return {"plan": null, "errors": ["lote: %d trabajos superan el maximo %d" % [total, MAX_JOBS]]}
	p._plan_jobs()
	return {"plan": p, "errors": []}


func _plan_jobs() -> void:
	jobs.clear()
	for si in scenarios.size():
		var s: Dictionary = scenarios[si]
		var reps := int(s.get("repetitions", repetitions))
		for r in reps:
			jobs.append({"index": jobs.size(), "scenario": si, "repetition": r, "seed": derive_seed(master_seed, seed_mode, str(s["key"]), str(s.get("group", "")), r)})


## Semilla de un trabajo: funcion pura de (maestra, modo, clave/grupo, repeticion).
static func derive_seed(master: int, mode: String, key: String, group: String, repetition: int) -> int:
	var token := "pair|%s|%d" % [group, repetition] if mode == "paired" else "job|%s|%d" % [key, repetition]
	return Rng.mix(master ^ Rng.fnv1a64(token))


func job_count() -> int:
	return jobs.size()


## Configuracion de DuelRunner del trabajo `index` (traza reducida salvo que se pida otra).
func job_config(index: int, trace: String = "reduced") -> Dictionary:
	var j: Dictionary = jobs[index]
	var s: Dictionary = scenarios[int(j["scenario"])]
	var cfg: Dictionary = base.duplicate(true)
	cfg["entities"] = (s["entities"] as Array).duplicate(true)
	for k in ["ruleset_overrides", "initial_overrides"]:
		if s.has(k):
			cfg[k] = Ruleset._merge(cfg.get(k, {}), s[k]) if cfg.has(k) else (s[k] as Dictionary).duplicate(true)
	cfg["seed"] = int(j["seed"])
	cfg["trace"] = trace
	return cfg


func to_dict() -> Dictionary:
	return {"schema": SCHEMA, "name": name, "master_seed": master_seed, "repetitions": repetitions, "seed_mode": seed_mode, "base": base, "scenarios": scenarios}


## Copia canonica: los numeros enteros se normalizan a int (JSON los devuelve como float), para que una ida y vuelta
## por JSON no cambie la huella.
static func _canon(v: Variant) -> Variant:
	if v is float and floorf(v) == v and absf(v) < 1.0e15:
		return int(v)
	if v is Array:
		return (v as Array).map(func(x): return _canon(x))
	if v is Dictionary:
		var d := {}
		for k in v:
			d[k] = _canon(v[k])
		return d
	return v


## Huella canonica del plan (configuracion + semillas): igual plan => igual huella.
func fingerprint() -> String:
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(JSON.stringify(_canon(to_dict()), "", true, true).to_utf8_buffer())
	for j in jobs:
		h.update(("%d:%d:%d\n" % [int(j["scenario"]), int(j["repetition"]), int(j["seed"])]).to_utf8_buffer())
	return h.finish().hex_encode()
