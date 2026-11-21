class_name DuelRunner
extends RefCounted
## Caso de uso: ejecutar un duelo (o combate multiparte) a partir de ficheros.
## Reutilizable por la CLI (tools/run_duel.gd), pruebas, y mas adelante UI/lotes.

const DEFAULT_RULESET := "res://content/rulesets/default_ruleset.json"
const DEFAULT_PROFILE := "res://content/balance/technical_profile.json"

## `config`: {"ruleset": path?, "profile": path?, "seed": int,
##   "entities": [{"path": "res://...json", "overrides": {"id":"x","team":"A"}},
##                 {"package": "ns/nombre", "version": "^1.0.0", "overrides": {"team":"B"}}],
##   "library": "user://library" (biblioteca de paquetes importados),
##   "trace": "full"|"reduced", "initial_overrides": {...},
##   "ruleset_overrides": {...}  (fusion profunda sobre el reglamento; comparar reglamentos, fase 7),
##   "ruleset_data": {...} / "profile_data": {...}: instantaneas INLINE (prioridad sobre `ruleset`/`profile`): los combates guardados no
##   dependen de archivos que cambien (fase 9); una entidad de biblioteca admite "hash" (huella fijada: `[contenido_alterado]` si no coincide),
##   una entidad suelta admite "data": {...} (entidad inline, en lugar de "path"),
##   cada entidad admite "patch": {...}: fusion PROFUNDA sobre sus datos (variar stats sueltos; `overrides` sustituye claves enteras),
##   "balance": {"profile": path_perfil_con_costes, "mode": "free"|"regulated", "budget": id}}  (fase 6, opcional)
## Devuelve {"ok": bool, "errors": Array, "result": CombatResult|null, "engine": CombatEngine|null, "balance": Array}
## `balance`: informes de valoracion (BalanceReport.to_dict) de cada entidad si se pidio; en modo reglamentado un PJ
## invalido (presupuesto/no evaluable) impide el combate.
static func run(config: Dictionary) -> Dictionary:
	var built := build_engine(config)
	if not built["ok"]:
		return {"ok": false, "errors": built["errors"], "result": null, "engine": null, "balance": built.get("balance", [])}
	var eng: CombatEngine = built["engine"]
	var res := eng.run()
	return {"ok": true, "errors": [], "result": res, "engine": eng, "balance": built.get("balance", [])}


static func build_engine(config: Dictionary) -> Dictionary:
	var errs: Array = []
	# `ruleset_data` / `profile_data`: instantaneas INLINE (combates guardados: reproducibles aunque cambien los archivos)
	var rules: Ruleset = Ruleset.from_dict(config["ruleset_data"]) if config.has("ruleset_data") else Ruleset.from_file(str(config.get("ruleset", DEFAULT_RULESET)))
	errs.append_array(rules.errors)
	if config.has("ruleset_overrides") and errs.is_empty():
		rules = Ruleset.from_dict(Ruleset._merge(rules.data, config["ruleset_overrides"]))
		errs.append_array(rules.errors)
	var profile: BalanceProfile = BalanceProfile.from_dict(config["profile_data"]) if config.has("profile_data") else BalanceProfile.from_file(str(config.get("profile", DEFAULT_PROFILE)))
	errs.append_array(profile.errors)
	var registry := OperationRegistry.new()
	var ents: Array = []
	var bal_cfg: Dictionary = config.get("balance", {})
	var bal_profile: BalanceProfile = null
	var bal_reports: Array = []
	if not bal_cfg.is_empty():
		bal_profile = BalanceProfile.from_dict(bal_cfg["profile_data"]) if bal_cfg.has("profile_data") else BalanceProfile.from_file(str(bal_cfg.get("profile", "")))
		errs.append_array(bal_profile.errors.map(func(e): return "perfil de equilibrio: " + str(e)))
	if errs.is_empty():
		var library := ContentLibrary.new(str(config.get("library", "user://library")))
		for spec in config.get("entities", []):
			if spec.has("package"):
				if spec.has("hash"): # contenido fijado: si la version almacenada cambio o se altero, no se reproduce en silencio
					var ent_e := library.resolve(str(spec["package"]), str(spec.get("version", "*")))
					if ent_e.is_empty() or str(ent_e.get("hash", "")) != str(spec["hash"]):
						errs.append("%s: [contenido_alterado] la version resuelta no coincide con la huella fijada %s" % [str(spec["package"]), str(spec["hash"]).substr(0, 12)])
						continue
				var pb := library.build_entity(str(spec["package"]), str(spec.get("version", "*")), rules, profile, registry, spec.get("overrides", {}), spec.get("patch", {}))
				for er in pb["errors"]:
					errs.append("%s: %s" % [str(spec["package"]), str(er)])
				if pb["entity"] != null:
					ents.append(pb["entity"])
					_balance(pb["data"], bal_profile, bal_cfg, rules, registry, str(spec["package"]), errs, bal_reports)
				continue
			# `data`: entidad INLINE (instantanea de un combate guardado); `path`: archivo
			var data: Variant = spec["data"] if spec.has("data") else EntityFactory.load_json(str(spec.get("path", "")))
			if not (data is Dictionary):
				errs.append("no se pudo leer la entidad '%s'" % str(spec.get("path", "(inline)")))
				continue
			if spec.has("patch"):
				data = Ruleset._merge(data, spec["patch"])
			var b := EntityFactory.build(data, profile, rules, registry, spec.get("overrides", {}))
			for er in b["errors"]:
				errs.append("%s: %s" % [str(spec.get("path", "(inline)")), str(er)])
			if b["entity"] != null:
				ents.append(b["entity"])
				var bd: Dictionary = (data as Dictionary).duplicate(true)
				bd.merge(spec.get("overrides", {}), true)
				_balance(bd, bal_profile, bal_cfg, rules, registry, str(spec.get("path", "(inline)")), errs, bal_reports)
	if not errs.is_empty():
		return {"ok": false, "errors": errs, "engine": null, "balance": bal_reports}
	var trace := EventLog.TraceLevel.REDUCED if str(config.get("trace", "full")) == "reduced" else EventLog.TraceLevel.FULL
	var eng := CombatEngine.new()
	eng.registry = registry
	var setup_errs := eng.setup(rules, ents, int(config.get("seed", 1)), trace, config.get("initial_overrides", {}))
	if not setup_errs.is_empty():
		return {"ok": false, "errors": setup_errs, "engine": null, "balance": bal_reports}
	return {"ok": true, "errors": [], "engine": eng, "balance": bal_reports}


## Valora una entidad si se pidio equilibrio; en modo reglamentado los hallazgos bloquean el combate.
static func _balance(data: Dictionary, prof: BalanceProfile, cfg: Dictionary, rules: Ruleset, registry: OperationRegistry, label: String, errs: Array, reports: Array) -> void:
	if prof == null:
		return
	var r := BalanceEvaluator.evaluate(data, prof, rules, registry, {"mode": cfg.get("mode", "free"), "budget": cfg.get("budget", "")})
	reports.append(r.to_dict())
	for e in r.technical_errors:
		errs.append("%s: equilibrio [tecnico] %s" % [label, str(e)])
	if str(cfg.get("mode", "free")) == "regulated":
		for e in r.errors:
			errs.append("%s: equilibrio %s" % [label, str(e)])
