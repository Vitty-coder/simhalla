class_name AppStorage
extends RefCounted
## Almacenamiento persistente de la aplicacion (PROJECT.md §11.1): biblioteca de paquetes versionados, reglamentos, perfiles de
## equilibrio, configuraciones de simulacion, combates guardados, lotes e informes, con indices locales, huellas de contenido,
## versiones inmutables y exportaciones portables (BundleIO). Todo en `user://` (compatible con PC y Android). Offline.
##
## Secciones (layout bajo `root`): library/ (paquetes), rulesets/, profiles/, configs/ (VersionedStore), battles/, batches/,
## reports/ (RecordStore), settings.json. No se sobrescribe contenido necesario para reproducir: un combate guardado FIJA las
## versiones exactas y huellas de sus paquetes y lleva instantaneas inline del reglamento, el perfil y las entidades sueltas;
## `remove_package` se rechaza mientras algun registro lo referencie.

const SETTINGS_SCHEMA := "simhalla.settings/1"
const DEFAULT_SETTINGS := {"schema": SETTINGS_SCHEMA, "locale": "es", "default_mode": "free", "default_budget": "standard", "workers": 0, "history": "summary", "default_profile": "builtin/reference_costs"}
const HISTORY_SCHEMA := "simhalla.history/1"
const HISTORY_MAX := 500
const BUILTIN_RULESET := "res://content/rulesets/default_ruleset.json"
const BUILTIN_PROFILES := {"builtin/technical_profile": "res://content/balance/technical_profile.json", "builtin/reference_costs": "res://content/balance/reference_costs.json"}

var root: String
var library: ContentLibrary
var rulesets: VersionedStore
var profiles: VersionedStore
var configs: VersionedStore
var battles: RecordStore
var batches: RecordStore
var reports: RecordStore


func _init(root_dir: String = "user://simhalla") -> void:
	root = root_dir
	library = ContentLibrary.new(root.path_join("library"))
	rulesets = VersionedStore.new(root.path_join("rulesets"), "ruleset", func(d: Dictionary) -> Array: return Ruleset.from_dict(d).errors)
	profiles = VersionedStore.new(root.path_join("profiles"), "profile", func(d: Dictionary) -> Array: return BalanceProfile.from_dict(d).errors)
	configs = VersionedStore.new(root.path_join("configs"), "config", AppStorage._validate_config)
	battles = RecordStore.new(root.path_join("battles"), "b", "battle")
	batches = RecordStore.new(root.path_join("batches"), "l", "batch")
	reports = RecordStore.new(root.path_join("reports"), "r", "report")


static func _validate_config(d: Dictionary) -> Array:
	var k := str(d.get("kind", ""))
	if k == "duel":
		if not (d.get("config", null) is Dictionary) or not ((d["config"] as Dictionary).get("entities", null) is Array):
			return ["config de duelo: requiere config.entities"]
		return []
	if k == "batch":
		if not (d.get("config", null) is Dictionary):
			return ["config de lote: requiere config"]
		return BatchPlan.from_dict(d["config"])["errors"]
	return ["kind debe ser duel o batch"]


## Instala (idempotente) el reglamento y los perfiles incluidos como elementos versionados `builtin/*`.
func install_builtins() -> Array:
	var errs: Array = []
	var rs: Variant = EntityFactory.load_json(BUILTIN_RULESET)
	if rs is Dictionary:
		var ver := Ruleset.from_dict(rs).version()
		var r := rulesets.put("builtin/default_ruleset", ver if SemVer.is_valid(ver) else "0.1.0", rs)
		if not bool(r["ok"]):
			errs.append(str(r["error"]))
	for id in BUILTIN_PROFILES:
		var d: Variant = EntityFactory.load_json(BUILTIN_PROFILES[id])
		if d is Dictionary:
			var r2 := profiles.put(id, str(d.get("version", "0.1.0")), d)
			if not bool(r2["ok"]):
				errs.append(str(r2["error"]))
	return errs


# --- Ajustes -------------------------------------------------------------------------------------------------------

func settings() -> Dictionary:
	var f := FileAccess.open(root.path_join("settings.json"), FileAccess.READ)
	var parsed: Variant = JSON.parse_string(f.get_as_text()) if f != null else null
	var s: Dictionary = DEFAULT_SETTINGS.duplicate(true)
	parsed = SchemaMigrator.default().upgraded(parsed)
	if parsed is Dictionary and SchemaMigrator.parse_id(parsed.get("schema", null)).get("version", 1) <= int(SchemaMigrator.default().current.get("settings", 1)):
		for k in DEFAULT_SETTINGS:
			if parsed.has(k):
				s[k] = parsed[k]
	return s


## Valida y guarda ajustes. Devuelve errores ([] = guardado).
func save_settings(s: Dictionary) -> Array:
	var errs: Array = []
	for k in s:
		if not DEFAULT_SETTINGS.has(str(k)):
			errs.append("ajuste desconocido '%s'" % str(k))
	if s.has("locale") and not LocaleService.LOCALES.has(str(s["locale"])):
		errs.append("locale '%s' no disponible (use: %s)" % [str(s["locale"]), ", ".join(LocaleService.LOCALES)])
	if s.has("default_mode") and not ["free", "regulated"].has(str(s["default_mode"])):
		errs.append("default_mode debe ser free o regulated")
	if s.has("workers") and (not (s["workers"] is int or s["workers"] is float) or int(s["workers"]) < 0 or int(s["workers"]) > BatchRunner.MAX_WORKERS):
		errs.append("workers debe estar entre 0 y %d" % BatchRunner.MAX_WORKERS)
	if s.has("history") and not ["none", "summary", "full"].has(str(s["history"])):
		errs.append("history debe ser none, summary o full")
	if not errs.is_empty():
		return errs
	var merged := settings()
	merged.merge(s, true)
	DirAccess.make_dir_recursive_absolute(root)
	var f := FileAccess.open(root.path_join("settings.json"), FileAccess.WRITE)
	if f == null:
		return ["no se pudo escribir los ajustes"]
	f.store_string(JSON.stringify(merged, "  ", true, true))
	f.close()
	return []


# --- Referencias y borrado protegido ------------------------------------------------------------------------------------

## Registros (combates, lotes, informes) que referencian el elemento. [{store, id, title}]
func references_to(ref_kind: String, id: String, version: String = "") -> Array:
	var out: Array = []
	for pair in [["battles", battles], ["batches", batches], ["reports", reports]]:
		for e in (pair[1] as RecordStore).list():
			for r in e["refs"]:
				if str(r.get("kind", "")) == ref_kind and str(r.get("id", "")) == id and (version == "" or str(r.get("version", "")) == version):
					out.append({"store": pair[0], "id": e["id"], "title": e["title"]})
					break
	return out


# --- Historial de la biblioteca ------------------------------------------------------------------------------------------------------
## Registro persistente de operaciones sobre la biblioteca y los registros (importar, borrar, bundles, exportar). `seq` es un contador
## (sin reloj); `saved_at` es solo informativo. Se conservan los ultimos HISTORY_MAX. Un historial ilegible se ignora (nunca bloquea).

func history_path() -> String:
	return root.path_join("history.json")


func history(limit: int = 0) -> Array:
	var out: Array = []
	if FileAccess.file_exists(history_path()):
		var d: Variant = JSON.parse_string(FileAccess.get_file_as_string(history_path()))
		d = SchemaMigrator.default().upgraded(d)
		if d is Dictionary and str(d.get("schema", "")) == HISTORY_SCHEMA and d.get("entries", null) is Array:
			for e in d["entries"]:
				if e is Dictionary and e.has("seq"):
					e["seq"] = int(e["seq"]) # JSON devuelve decimales
					out.append(e)
	if limit > 0 and out.size() > limit:
		out = out.slice(out.size() - limit)
	return out


## Anade una entrada. Devuelve su `seq` (0 si no se pudo escribir; el historial es auxiliar y no falla la operacion principal).
func log_event(action: String, target: String, detail: String = "") -> int:
	var all := history()
	var seq := (int(all[-1]["seq"]) + 1) if not all.is_empty() else 1
	all.append({"seq": seq, "action": action, "target": target, "detail": detail, "saved_at": int(Time.get_unix_time_from_system())})
	if all.size() > HISTORY_MAX:
		all = all.slice(all.size() - HISTORY_MAX)
	DirAccess.make_dir_recursive_absolute(root)
	var tmp := history_path() + ".tmp"
	var f := FileAccess.open(tmp, FileAccess.WRITE)
	if f == null:
		return 0
	f.store_string(JSON.stringify({"schema": HISTORY_SCHEMA, "entries": all}, "  "))
	f.close()
	if DirAccess.rename_absolute(tmp, history_path()) != OK:
		return 0
	return seq


## Elimina una version de paquete; se rechaza si algun registro depende de ella (salvo `force`).
func remove_package(id: String, version: String, force: bool = false) -> String:
	var refs := references_to("package", id, version)
	if not refs.is_empty() and not force:
		return "[referenciado] %s@%s lo usan %d registro(s): %s" % [id, version, refs.size(), ", ".join(refs.slice(0, 3).map(func(r): return "%s/%s" % [r["store"], r["id"]]))]
	var err := library.remove(id, version)
	if err == "":
		log_event("remove_package", "%s@%s" % [id, version], "forzado" if force and not refs.is_empty() else "")
	return err


## Elimina un registro; se rechaza si otro depende de el (p. ej. un combate con informes).
func remove_record(store: String, id: String) -> String:
	var st: RecordStore = {"battles": battles, "batches": batches, "reports": reports}.get(store, null)
	if st == null:
		return "[almacen] desconocido '%s'" % store
	var kind_ref: String = {"battles": "battle", "batches": "batch", "reports": "report"}[store]
	var deps := references_to(kind_ref, id)
	if not deps.is_empty():
		return "[referenciado] %s %s lo usan: %s" % [store, id, ", ".join(deps.map(func(r): return "%s/%s" % [r["store"], r["id"]]))]
	var err := st.remove(id)
	if err == "":
		log_event("remove_record", "%s/%s" % [store, id])
	return err


# --- Fijar configuraciones (reproducibilidad) ------------------------------------------------------------------------------

## Fija una lista de especificaciones de entidad: paquetes a version exacta y huella; archivos sueltos como `data` inline.
## {"specs", "refs", "errors"}.
func pin_entities(specs: Array) -> Dictionary:
	var errs: Array = []
	var refs: Array = []
	var out: Array = []
	for spec in specs:
		var s: Dictionary = (spec as Dictionary).duplicate(true)
		if s.has("package"):
			var e := library.resolve(str(s["package"]), str(s.get("version", "*")))
			if e.is_empty():
				errs.append("[no_encontrado] ningun paquete '%s' cumple '%s'" % [str(s["package"]), str(s.get("version", "*"))])
			else:
				s["version"] = e["version"]
				s["hash"] = e["hash"]
				refs.append({"kind": "package", "id": e["id"], "version": e["version"], "hash": e["hash"]})
		elif s.has("path"):
			var d: Variant = EntityFactory.load_json(str(s["path"]))
			if d is Dictionary:
				s["data"] = d
				s["source_path"] = s["path"]
				s.erase("path")
			else:
				errs.append("no se pudo leer la entidad '%s'" % str(s["path"]))
		out.append(s)
	return {"specs": out, "refs": refs, "errors": errs}


## Fija una configuracion de duelo para poder reproducirla despues: paquetes a version exacta y huella, entidades sueltas y
## reglamento/perfil como instantaneas inline. {"ok","config","refs","errors"}.
func pin_config(config: Dictionary) -> Dictionary:
	var c: Dictionary = config.duplicate(true)
	var pe := pin_entities(c.get("entities", []))
	var errs: Array = pe["errors"]
	c["entities"] = pe["specs"]
	if not c.has("ruleset_data"):
		var rs := Ruleset.from_file(str(c.get("ruleset", BUILTIN_RULESET)))
		if not rs.is_valid():
			errs.append("reglamento invalido: " + "; ".join(rs.errors))
		c["ruleset_data"] = rs.data
	c.erase("ruleset")
	if not c.has("profile_data"):
		var pf := BalanceProfile.from_file(str(c.get("profile", DuelRunner.DEFAULT_PROFILE)))
		if not pf.is_valid():
			errs.append("perfil invalido: " + "; ".join(pf.errors))
		c["profile_data"] = pf.to_dict()
	c.erase("profile")
	c["library"] = library.root
	if c.has("seed"):
		c["seed"] = str(c["seed"])
	return {"ok": errs.is_empty(), "config": c, "refs": pe["refs"], "errors": errs}


# --- Combates guardados ---------------------------------------------------------------------------------------------------------

## Guarda un combate TERMINADO de una sesion. `config` debe estar fijada (`pin_config`). options: {title, with_trace, note}.
func save_battle(session: SimulationSession, config: Dictionary, options: Dictionary = {}) -> Dictionary:
	if not session.is_finished():
		return {"ok": false, "id": "", "error": "el combate no ha terminado"}
	var r := session.result()
	var refs: Array = []
	for spec in config.get("entities", []):
		if (spec as Dictionary).has("package") and (spec as Dictionary).has("hash"):
			refs.append({"kind": "package", "id": spec["package"], "version": spec.get("version", ""), "hash": spec["hash"]})
	var rec := {"schema": "simhalla.battle/1", "config": config, "seed": str(r.seed_value), "engine_version": r.engine_version, "ruleset_hash": r.ruleset_hash,
		"log_hash": r.log_hash, "result": {"outcome": r.outcome, "winner_team": r.winner_team, "reason": r.reason, "kind": r.kind, "turns": r.turns, "actions": r.actions,
		"events": r.events, "end_time": r.end_time, "error": r.error}, "steps": session.step_count, "note": str(options.get("note", ""))}
	var files := {"record.json": JSON.stringify(rec, "  ", true, true)}
	if bool(options.get("with_trace", false)):
		files["trace.json"] = JSON.stringify(session.engine.log.events, "", true, true)
	var title := str(options.get("title", "Combate %s" % r.log_hash.substr(0, 8)))
	var a := battles.add(title, files, refs, {"outcome": r.outcome, "winner_team": r.winner_team, "log_hash": r.log_hash, "engine_version": r.engine_version, "turns": r.turns})
	return a


func load_battle(id: String) -> Dictionary:
	var verr := battles.verify(id)
	if verr != "":
		return {"ok": false, "record": {}, "error": verr}
	var rec: Variant = battles.read_json(id, "record.json")
	if not (rec is Dictionary):
		return {"ok": false, "record": {}, "error": "[json] record.json ilegible"}
	return {"ok": true, "record": rec, "error": ""}


## Reproduce un combate guardado con la configuracion FIJADA. {"ok","session","matches","warnings","errors"}.
func replay_battle(id: String) -> Dictionary:
	var lb := load_battle(id)
	if not bool(lb["ok"]):
		return {"ok": false, "session": null, "matches": false, "warnings": [], "errors": [lb["error"]]}
	var rec: Dictionary = lb["record"]
	var warns: Array = []
	if str(rec["engine_version"]) != CombatEngine.ENGINE_VERSION:
		warns.append("el combate se guardo con el motor %s y esta es la %s: no se garantiza el mismo resultado" % [str(rec["engine_version"]), CombatEngine.ENGINE_VERSION])
	var cfg: Dictionary = (rec["config"] as Dictionary).duplicate(true)
	cfg["library"] = library.root # el contenido fijado vive en la biblioteca actual (o importado de un paquete portable)
	var o := SimulationSession.open(cfg)
	if not bool(o["ok"]):
		return {"ok": false, "session": null, "matches": false, "warnings": warns, "errors": o["errors"]}
	var s: SimulationSession = o["session"]
	var check := SimulationSession.open(cfg)["session"] as SimulationSession
	var final := check.run_to_end()
	var matches := final.log_hash == str(rec["log_hash"])
	if not matches:
		warns.append("el registro reproducido NO coincide con el guardado (log_hash distinto)")
	return {"ok": true, "session": s, "matches": matches, "warnings": warns, "errors": []}


# --- Lotes e informes -------------------------------------------------------------------------------------------------------------

func save_batch(result: BatchResult, title: String, library_refs: Array = []) -> Dictionary:
	var plan_text := JSON.stringify(result.plan, "  ", true, true)
	var st := result.to_storable()
	var files := {"plan.json": plan_text, "result.json": JSON.stringify(st, "", true, true)}
	var refs: Array = library_refs.duplicate(true)
	return batches.add(title, files, refs, {"status": result.status, "executed": result.executed, "total_jobs": result.total_jobs, "fingerprint": result.fingerprint, "engine_version": result.engine_version})


func load_batch(id: String) -> Dictionary:
	var verr := batches.verify(id)
	if verr != "":
		return {"ok": false, "result": null, "error": verr}
	var d: Variant = batches.read_json(id, "result.json")
	if not (d is Dictionary):
		return {"ok": false, "result": null, "error": "[json] result.json ilegible"}
	return {"ok": true, "result": BatchResult.from_dict(d), "error": ""}


## Guarda un informe (modelo) en los tres formatos. refs: [{kind: "battle"|"batch", id}]. {"ok","id","error"}.
func save_report(model: Dictionary, title: String, refs: Array = []) -> Dictionary:
	var files := {"report.json": ReportExporter.to_json(model), "report.md": ReportExporter.to_markdown(model), "report.html": ReportExporter.to_html(model)}
	return reports.add(title, files, refs, {"report_kind": str(model.get("kind", "")), "content_hash": ReportExporter.content_hash(model)})


## Comprueba un informe guardado: huella de archivos + huella del modelo + (si referencia un lote guardado) recalculo desde sus registros.
func verify_report(id: String) -> Array:
	var errs: Array = []
	var verr := reports.verify(id)
	if verr != "":
		return [verr]
	var e := reports.entry(id)
	var model: Variant = reports.read_json(id, "report.json")
	if not (model is Dictionary):
		return ["[json] report.json ilegible"]
	if ReportExporter.content_hash(model) != str(e["meta"]["content_hash"]):
		errs.append("la huella del modelo no coincide con la guardada")
	if str(model.get("kind", "")) == "batch":
		errs.append_array(ReportVerifier.check_batch(model))
		for r in e["refs"]:
			if str(r.get("kind", "")) == "batch":
				var lb := load_batch(str(r["id"]))
				if bool(lb["ok"]):
					errs.append_array(ReportVerifier.verify_batch(model, lb["result"]))
	else:
		errs.append_array(ReportVerifier.check_individual(model))
	return errs
