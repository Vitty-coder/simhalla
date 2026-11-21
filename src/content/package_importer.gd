class_name PackageImporter
extends RefCounted
## Valida e importa paquetes de contenido (carpeta o ZIP) a la biblioteca.
##
## Validacion en capas, TODA antes de incorporar nada:
##   1. lectura segura (rutas, tamanos, enlaces, bombas ZIP)      -> PackageSource
##   2. archivos conocidos segun el tipo; los demas se rechazan
##   3. JSON valido (UTF-8) y esquemas publicos de `schemas/`
##   4. coherencia: manifiesto, dependencias (existen, tipos, version), imports
##   5. validacion tecnica: se construye la entidad/habilidades/IA como en combate
##   6. assets (extension y firma de archivo)
## No se ejecuta ningun script durante la importacion: los `scripts/*.sim` solo se
## compilan (sintaxis, lista permitida de la API, referencias y contexto). El contenido valido queda inmutable
## en la biblioteca, versionado por id@version y con huella.

const SCHEMA_OF := {
	"manifest.json": "manifest.schema.json", "character.json": "character.schema.json",
	"abilities.json": "abilities.schema.json", "resources.json": "resources.schema.json",
	"ai.json": "ai.schema.json", "artifact.json": "artifact.schema.json",
	"effects.json": "effects.schema.json", "summons.json": "summons.schema.json",
}
const REQUIRED_BY_TYPE := {"character": ["character.json"], "abilities": ["abilities.json"], "ai": ["ai.json"]}
const ALLOWED_BY_TYPE := {
	"character": ["manifest.json", "README.md", "character.json", "abilities.json", "resources.json", "ai.json", "artifact.json", "effects.json", "summons.json"],
	"abilities": ["manifest.json", "README.md", "abilities.json"],
	"ai": ["manifest.json", "README.md", "ai.json"],
}
const UNSUPPORTED := {"effects.json": "estados propios en paquetes de biblioteca (solo los personajes los definen)", "summons.json": "invocaciones en paquetes de biblioteca (solo los personajes las definen)"}
const ASSET_EXT := ["png", "jpg", "jpeg", "webp"]

var library: ContentLibrary
var rules: Ruleset
var profile: BalanceProfile
var registry: OperationRegistry = OperationRegistry.new()
var schemas: SchemaValidator = SchemaValidator.new()
## Valoracion de equilibrio opcional (fase 6): {"profile": BalanceProfile con costes, "mode": "free"|"regulated", "budget": id}.
## Sin esto el importador solo valida lo tecnico. En modo reglamentado un paquete que excede el presupuesto o tiene
## componentes no evaluables se RECHAZA ([equilibrio]); en modo libre solo se avisa.
var balance: Dictionary = {}


func _init(lib: ContentLibrary, ruleset: Ruleset = null, balance: BalanceProfile = null) -> void:
	library = lib
	rules = ruleset if ruleset != null else Ruleset.from_file("res://content/rulesets/default_ruleset.json")
	profile = balance if balance != null else BalanceProfile.from_file("res://content/balance/technical_profile.json")


## Valida sin almacenar.
func validate(path: String) -> ImportReport:
	return _run(path, false)


## Valida y, si es correcto, almacena en la biblioteca.
func import_package(path: String) -> ImportReport:
	return _run(path, true)


func _run(path: String, store: bool) -> ImportReport:
	var rep := ImportReport.new()
	var src := PackageSource.read(path)
	for e in src["errors"]:
		rep.error(e)
	var files: Dictionary = src["files"]
	if files.is_empty():
		if rep.errors.is_empty():
			rep.error("[vacio] el paquete no contiene archivos")
		return rep
	if not files.has("manifest.json"):
		rep.error("manifest.json: [falta_manifiesto] el paquete debe contener manifest.json en su raiz")
		return rep

	var parsed := _parse_json_files(files, rep)
	if not parsed.has("manifest.json"):
		return rep
	var manifest: Dictionary = parsed["manifest.json"]
	var mf_errs := schemas.validate("manifest.schema.json", manifest)
	for e in mf_errs:
		rep.error("manifest.json: [esquema] " + e)
	if not mf_errs.is_empty():
		return rep
	rep.id = str(manifest["id"])
	rep.version = str(manifest["version"])
	rep.type = str(manifest["type"])
	_check_manifest(manifest, rep)
	_check_file_set(files, rep)
	for fname in SCHEMA_OF:
		if fname != "manifest.json" and parsed.has(fname):
			for e in schemas.validate(SCHEMA_OF[fname], parsed[fname]):
				rep.error("%s: [esquema] %s" % [fname, e])
	rep.hash = PackageSource.content_hash(files)
	if not rep.ok():
		return rep

	_check_semantics(parsed, manifest, files, rep)
	if not rep.ok():
		return rep

	if store:
		var existed := library.has(rep.id, rep.version)
		var err := library.store(files, rep.id, rep.version, rep.hash)
		if err != "":
			rep.error(err)
		else:
			rep.already_present = existed
			rep.stored = not existed
	return rep


func _parse_json_files(files: Dictionary, rep: ImportReport) -> Dictionary:
	var parsed := {}
	var names: Array = files.keys()
	names.sort()
	for name in names:
		if not str(name).ends_with(".json"):
			continue
		var bytes: PackedByteArray = files[name]
		if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
			rep.error("%s: [codificacion] el archivo no debe empezar por BOM" % name)
			continue
		var text := bytes.get_string_from_utf8()
		if text.to_utf8_buffer() != bytes:
			rep.error("%s: [codificacion] no es UTF-8 valido" % name)
			continue
		if text.length() > 0 and text.unicode_at(0) == 0xFEFF:
			rep.error("%s: [codificacion] el archivo no debe empezar por BOM" % name)
			continue
		var j := JSON.new()
		if j.parse(text) != OK:
			rep.error("%s: [json] linea %d: %s" % [name, j.get_error_line(), j.get_error_message()])
			continue
		if not (j.data is Dictionary):
			rep.error("%s: [json] la raiz debe ser un objeto" % name)
			continue
		var mig := SchemaMigrator.default().migrate(j.data)
		if not bool(mig["ok"]):
			for e in mig["errors"]:
				rep.error("%s: %s" % [name, e])
			continue
		if bool(mig["migrated"]):
			rep.warnings.append("%s: [migrado] esquema actualizado en memoria de /%d a /%d (el archivo original no se modifica)" % [name, mig["from"], mig["to"]])
		parsed[name] = mig["data"]
	return parsed


func _check_manifest(m: Dictionary, rep: ImportReport) -> void:
	var seen := {}
	for d in m.get("dependencies", []):
		var did := str(d["id"])
		if did == rep.id:
			rep.error("manifest.json: [dependencia_ciclica] el paquete depende de si mismo")
		if seen.has(did):
			rep.error("manifest.json: [dependencia_duplicada] '%s' aparece mas de una vez" % did)
		seen[did] = true
	if m.has("min_engine_version") and SemVer.compare(str(m["min_engine_version"]), CombatEngine.ENGINE_VERSION) > 0:
		rep.error("manifest.json: [motor_incompatible] requiere motor >= %s (actual %s)" % [str(m["min_engine_version"]), CombatEngine.ENGINE_VERSION])
	if rep.type != "character" and not m.get("dependencies", []).is_empty():
		rep.error("manifest.json: [dependencias] los paquetes de tipo '%s' no admiten dependencias todavia" % rep.type)


func _check_file_set(files: Dictionary, rep: ImportReport) -> void:
	var type := rep.type
	for req in REQUIRED_BY_TYPE[type]:
		if not files.has(req):
			rep.error("%s: [falta_archivo] obligatorio para paquetes de tipo '%s'" % [req, type])
	var names: Array = files.keys()
	names.sort()
	for n in names:
		var name := str(n)
		if ALLOWED_BY_TYPE[type].has(name):
			continue
		if UNSUPPORTED.has(name):
			rep.error("%s: [no_soportado] %s todavia no esta soportado" % [name, UNSUPPORTED[name]])
		elif name.begins_with("scripts/"):
			if type != "character":
				rep.error("%s: [no_soportado] los scripts solo se admiten en paquetes de personaje" % name)
			elif RegEx.create_from_string(PackageSource.SCRIPT_RE).search(name) == null:
				rep.error("%s: [script] nombre no valido (use scripts/<id>.sim con id en minusculas, digitos y _)" % name)
			else:
				_check_script_text(name, files[name], rep)
		elif name.begins_with("assets/") and type == "character":
			_check_asset(name, files[name], rep)
		else:
			rep.error("%s: [archivo_desconocido] no forma parte del formato de paquete '%s'" % [name, type])


func _check_script_text(name: String, bytes: PackedByteArray, rep: ImportReport) -> void:
	if bytes.size() >= 3 and bytes[0] == 0xEF and bytes[1] == 0xBB and bytes[2] == 0xBF:
		rep.error("%s: [codificacion] el script no debe empezar por BOM" % name)
		return
	var text := bytes.get_string_from_utf8()
	if text.to_utf8_buffer() != bytes:
		rep.error("%s: [codificacion] el script no es UTF-8 valido" % name)


func _check_asset(name: String, bytes: PackedByteArray, rep: ImportReport) -> void:
	var ext := name.get_extension().to_lower()
	if not ASSET_EXT.has(ext):
		rep.error("%s: [asset] extension no admitida (use %s)" % [name, ", ".join(ASSET_EXT)])
		return
	var ok := false
	match ext:
		"png":
			ok = bytes.size() > 8 and bytes[0] == 0x89 and bytes[1] == 0x50 and bytes[2] == 0x4E and bytes[3] == 0x47
		"jpg", "jpeg":
			ok = bytes.size() > 3 and bytes[0] == 0xFF and bytes[1] == 0xD8 and bytes[2] == 0xFF
		"webp":
			ok = bytes.size() > 12 and bytes.slice(0, 4).get_string_from_ascii() == "RIFF" and bytes.slice(8, 12).get_string_from_ascii() == "WEBP"
	if not ok:
		rep.error("%s: [asset] el contenido no corresponde a un archivo .%s valido" % [name, ext])


func _check_semantics(parsed: Dictionary, manifest: Dictionary, files: Dictionary, rep: ImportReport) -> void:
	match rep.type:
		"abilities":
			_check_abilities(parsed["abilities.json"]["abilities"], "abilities.json", rep)
			if parsed["abilities.json"]["abilities"].is_empty():
				rep.error("abilities.json: [vacio] debe definir al menos una habilidad")
		"ai":
			var ai: Dictionary = parsed["ai.json"]
			if not ai.has("strategies") or ai.has("ai"):
				rep.error("ai.json: [esquema] un paquete de IA debe definir 'strategies' (y no 'ai')")
				return
			for sid in ai["strategies"]:
				var r := AIFactory.build(ai["strategies"][sid])
				for e in r["errors"]:
					rep.error("ai.json: strategies.%s: %s" % [sid, str(e)])
		"character":
			if parsed.has("ai.json") and parsed["ai.json"].has("strategies"):
				rep.error("ai.json: [esquema] en un personaje use 'ai' (no 'strategies')")
				return
			if parsed.has("abilities.json"):
				_check_abilities(parsed["abilities.json"]["abilities"], "abilities.json", rep)
			var comp := EntityComposer.compose(parsed, manifest, library, PackageSource.scripts_of(files))
			for e in comp["errors"]:
				rep.error(str(e))
			for w in comp["warnings"]:
				rep.warnings.append(str(w))
			rep.dependencies = comp["deps"]
			if comp["errors"].is_empty() and not balance.is_empty():
				var d: Dictionary = (comp["data"] as Dictionary).duplicate(true)
				d["id"] = rep.id
				d["team"] = "balance"
				var br := BalanceEvaluator.evaluate(d, balance["profile"], rules, registry, {"mode": balance.get("mode", "free"), "budget": balance.get("budget", "")})
				rep.balance = br.to_dict()
				for e in br.technical_errors:
					rep.error("equilibrio: [tecnico] " + str(e))
				if str(balance.get("mode", "free")) == "regulated":
					for e in br.errors:
						rep.error("equilibrio: " + str(e))
				for w in br.warnings:
					rep.warnings.append("equilibrio: " + str(w))
			if comp["errors"].is_empty():
				var b := EntityFactory.build(comp["data"], profile, rules, registry)
				for e in b["errors"]:
					rep.error("personaje: [validacion] " + str(e))
				for w in b["warnings"]:
					rep.warnings.append(str(w))
				if b["entity"] != null:
					# Ensayo en un motor real: referencias a estados/plantillas, estados nativos, etc.
					var probe := EntityFactory.build({"id": "probe_enemy", "team": "probe", "ai": {"type": "passive"}, "basic_attack": false}, profile, rules, registry)
					(b["entity"] as CombatEntity).team = "probe_a"
					for e in CombatEngine.new().setup(rules, [b["entity"], probe["entity"]], 1):
						rep.error("personaje: [validacion] " + str(e))


func _check_abilities(list: Array, file: String, rep: ImportReport) -> void:
	var seen := {}
	for i in list.size():
		var a: Dictionary = list[i]
		var id := str(a.get("id", ""))
		if seen.has(id):
			rep.error("%s: abilities[%d]: [duplicada] id '%s' repetido" % [file, i, id])
		seen[id] = true
		var r := AbilityDef.from_dict(a, registry)
		for e in r["errors"]:
			rep.error("%s: abilities[%d]: %s" % [file, i, str(e)])
