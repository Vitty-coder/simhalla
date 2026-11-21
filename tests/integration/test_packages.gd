extends TestCase
## Paquetes de contenido: importacion, validacion, dependencias, seguridad, biblioteca.

const PKG := "res://content/packages/"
const TMP := "user://_tests_phase2"

var _n := 0


# --- utilidades ---------------------------------------------------------------------

func _dir() -> String:
	_n += 1
	return "%s/t%d_%d" % [TMP, Time.get_ticks_usec(), _n]


func _lib() -> ContentLibrary:
	return ContentLibrary.new(_dir() + "/lib")


func _imp(lib: ContentLibrary) -> PackageImporter:
	return PackageImporter.new(lib)


## Escribe un paquete en disco: {ruta: texto | PackedByteArray}. Devuelve la carpeta.
func _pkg(files: Dictionary) -> String:
	var d := _dir() + "/pkg"
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


func _mf(id: String = "t/hero", version: String = "1.0.0", type: String = "character", extra: Dictionary = {}) -> String:
	var m := {"schema": "simhalla.manifest/1", "id": id, "version": version, "type": type, "name": "Test"}
	m.merge(extra, true)
	return JSON.stringify(m)


func _char(extra: Dictionary = {}) -> String:
	var c := {"schema": "simhalla.character/1", "name": "Heroe", "stats": {"ATK": 120}}
	c.merge(extra, true)
	return JSON.stringify(c)


func _hero(extra_files: Dictionary = {}, mf: String = "", ch: String = "") -> String:
	var files := {"manifest.json": mf if mf != "" else _mf(), "character.json": ch if ch != "" else _char()}
	files.merge(extra_files, true)
	return _pkg(files)


func _errs(rep: ImportReport) -> String:
	return "\n".join(rep.errors)


func _import_examples(lib: ContentLibrary) -> void:
	var imp := _imp(lib)
	for n in ["core_spells", "basic_ai", "arcane_duelist", "iron_vanguard"]:
		var rep := imp.import_package(PKG + n)
		assert_true(rep.ok(), "%s: %s" % [n, _errs(rep)])


func _cleanup() -> void:
	ContentLibrary._remove_tree(TMP)


# --- criterio de aceptacion de la fase 2 ------------------------------------------------

func test_import_two_external_characters_and_fight() -> void:
	var lib := _lib()
	_import_examples(lib)
	var ids: Array = lib.list().map(func(e): return e["id"] + "@" + e["version"])
	assert_eq(ids, ["examples/arcane_duelist@1.0.0", "examples/basic_ai@1.0.0", "examples/core_spells@1.2.0", "examples/iron_vanguard@1.0.0"])
	var cfg := {"seed": 3, "library": lib.root, "entities": [
		{"package": "examples/arcane_duelist", "version": "^1.0.0", "overrides": {"team": "A"}},
		{"package": "examples/iron_vanguard", "overrides": {"team": "B"}}]}
	var out := DuelRunner.run(cfg)
	assert_true(out["ok"], str(out["errors"]))
	var r: CombatResult = out["result"]
	assert_true(r.is_win(), "%s %s" % [r.outcome, r.reason])
	var again: CombatResult = DuelRunner.run(cfg)["result"]
	assert_eq(r.log_hash, again.log_hash, "mismo paquete + semilla = mismo combate")
	_cleanup()


func test_package_content_drives_behaviour_and_traceability() -> void:
	var lib := _lib()
	_import_examples(lib)
	var out := DuelRunner.run({"seed": 3, "library": lib.root, "entities": [
		{"package": "examples/arcane_duelist", "overrides": {"team": "A"}}, {"package": "examples/iron_vanguard", "overrides": {"team": "B"}}]})
	var eng: CombatEngine = out["engine"]
	var mage: CombatEntity = eng.get_entity("examples/arcane_duelist")
	# artefacto: MAG 200 + 30 ; CRIT 0.15 + 0.05
	assert_almost(mage.stats.get_value("MAG"), 230.0)
	assert_almost(mage.stats.get_value("CRIT"), 0.2, 1e-12)
	assert_almost(mage.stats.get_base("MAG"), 200.0, 1e-12, "la base no cambia: el artefacto es un modificador con origen")
	var ids: Array = mage.abilities.map(func(a): return a.id)
	for want in ["basic_attack", "fireball", "frost_lance", "mend", "staff_strike"]:
		assert_contains(ids, want)
	assert_almost((mage.get_resource("mana") as ResourceState).max_value, 80.0)
	# la IA importada usa fireball
	var used: Array = eng.log.of_type(EventTypes.ACTION_RESOLVED).filter(func(e): return e["source"] == mage.id).map(func(e): return e["data"]["ability"])
	assert_contains(used, "fireball")
	# trazabilidad: version + huella + dependencias exactas en combat_started
	var started: Dictionary = eng.log.of_type(EventTypes.COMBAT_STARTED)[0]
	var content: Dictionary = {}
	for e in started["data"]["entities"]:
		if e["id"] == mage.id:
			content = e["content"]
	assert_eq(content["version"], "1.0.0")
	assert_eq(content["hash"].length(), 64)
	assert_eq(content["dependencies"].size(), 2)
	assert_eq(content["dependencies"][0]["id"], "examples/basic_ai")
	_cleanup()


func test_changing_package_version_changes_combat_fingerprint() -> void:
	var lib := _lib()
	_import_examples(lib)
	var cfg := {"seed": 5, "library": lib.root, "entities": [
		{"package": "examples/iron_vanguard", "overrides": {"team": "A"}}, {"package": "examples/arcane_duelist", "overrides": {"team": "B"}}]}
	var h1: String = DuelRunner.run(cfg)["result"].log_hash
	# nueva version del vanguardia con otro ATK
	var v2 := _pkg({"manifest.json": _mf("examples/iron_vanguard", "1.1.0"), "character.json": _char({"name": "Vanguardia", "stats": {"HP": 1500, "ATK": 200, "DEF": 200}})})
	assert_true(_imp(lib).import_package(v2).ok())
	var h2: String = DuelRunner.run(cfg)["result"].log_hash
	assert_ne(h1, h2, "se resuelve la 1.1.0 (mas alta)")
	cfg["entities"][0]["version"] = "1.0.0"
	assert_eq(DuelRunner.run(cfg)["result"].log_hash, h1, "fijando 1.0.0 se reproduce el combate antiguo")
	_cleanup()


# --- biblioteca y versiones ------------------------------------------------------------------

func test_import_is_idempotent_and_versions_are_immutable() -> void:
	var lib := _lib()
	var imp := _imp(lib)
	var p := _hero()
	var r1 := imp.import_package(p)
	assert_true(r1.ok() and r1.stored and not r1.already_present, _errs(r1))
	var r2 := imp.import_package(p)
	assert_true(r2.ok() and r2.already_present and not r2.stored, "mismo contenido: idempotente")
	assert_eq(r1.hash, r2.hash)
	var changed := _hero({}, "", _char({"stats": {"ATK": 999}}))
	var r3 := imp.import_package(changed)
	assert_false(r3.ok())
	assert_contains(_errs(r3), "version_conflicto")
	assert_eq(lib.entry("t/hero", "1.0.0")["hash"], r1.hash, "el contenido original sigue intacto")
	var r4 := imp.import_package(_hero({}, _mf("t/hero", "1.0.1")))
	assert_true(r4.ok(), _errs(r4))
	assert_eq(lib.versions("t/hero"), ["1.0.0", "1.0.1"])
	_cleanup()


func test_resolve_picks_highest_satisfying() -> void:
	var lib := _lib()
	var imp := _imp(lib)
	for v in ["1.0.0", "1.4.2", "1.10.0", "2.0.0", "2.1.0-beta"]:
		assert_true(imp.import_package(_hero({}, _mf("t/hero", v))).ok(), v)
	assert_eq(lib.resolve("t/hero", "^1.0.0")["version"], "1.10.0", "orden numerico")
	assert_eq(lib.resolve("t/hero", "~1.4.0")["version"], "1.4.2")
	assert_eq(lib.resolve("t/hero", "*")["version"], "2.0.0", "las prereleases no se resuelven por defecto")
	assert_eq(lib.resolve("t/hero", ">=2.0.0")["version"], "2.0.0")
	assert_eq(lib.resolve("t/hero", "2.1.0-beta")["version"], "2.1.0-beta", "salvo peticion expresa")
	assert_true(lib.resolve("t/hero", "^3.0.0").is_empty())
	assert_true(lib.resolve("t/nadie", "*").is_empty())
	_cleanup()


func test_validate_does_not_store_and_invalid_import_leaves_nothing() -> void:
	var lib := _lib()
	var imp := _imp(lib)
	var ok := imp.validate(_hero())
	assert_true(ok.ok() and not ok.stored)
	assert_eq(lib.list().size(), 0)
	var bad := imp.import_package(_hero({}, "", _char({"poder": 1})))
	assert_false(bad.ok())
	assert_eq(lib.list().size(), 0, "importacion atomica: nada a medias")
	_cleanup()


func test_tampering_is_detected_on_load() -> void:
	var lib := _lib()
	assert_true(_imp(lib).import_package(_hero()).ok())
	var f := FileAccess.open(lib.entry_dir("t/hero", "1.0.0").path_join("character.json"), FileAccess.WRITE)
	f.store_string(_char({"stats": {"ATK": 99999}}))
	f.close()
	var pkg := lib.load_package("t/hero", "1.0.0")
	assert_contains(" ".join(pkg["errors"]), "integridad")
	var b := lib.build_entity("t/hero", "*", Ruleset.from_dict({}), BalanceProfile.default_profile(), OperationRegistry.new())
	assert_true(b["entity"] == null)
	assert_contains(" ".join(b["errors"]), "integridad")
	_cleanup()


# --- dependencias -------------------------------------------------------------------------------

func _spells(lib: ContentLibrary) -> void:
	assert_true(_imp(lib).import_package(PKG + "core_spells").ok())


func test_missing_dependency_rejected() -> void:
	var lib := _lib()
	var mf := _mf("t/hero", "1.0.0", "character", {"dependencies": [{"id": "examples/core_spells", "version": "^1.0.0"}]})
	var rep := _imp(lib).import_package(_hero({}, mf))
	assert_false(rep.ok())
	assert_contains(_errs(rep), "no encontrada")
	_cleanup()


func test_dependency_version_unsatisfied_and_wrong_type() -> void:
	var lib := _lib()
	_spells(lib)
	var mf := _mf("t/hero", "1.0.0", "character", {"dependencies": [{"id": "examples/core_spells", "version": "^2.0.0"}]})
	assert_contains(_errs(_imp(lib).import_package(_hero({}, mf))), "no encontrada")
	assert_true(_imp(lib).import_package(PKG + "iron_vanguard").ok())
	var mf2 := _mf("t/hero", "1.0.0", "character", {"dependencies": [{"id": "examples/iron_vanguard", "version": "*"}]})
	assert_contains(_errs(_imp(lib).import_package(_hero({}, mf2))), "solo se admiten 'abilities' y 'ai'")
	_cleanup()


func test_self_and_duplicate_dependency_rejected() -> void:
	var lib := _lib()
	_spells(lib)
	var self_dep := _mf("t/hero", "1.0.0", "character", {"dependencies": [{"id": "t/hero", "version": "*"}]})
	assert_contains(_errs(_imp(lib).import_package(_hero({}, self_dep))), "dependencia_ciclica")
	var dup := _mf("t/hero", "1.0.0", "character", {"dependencies": [{"id": "examples/core_spells", "version": "*"}, {"id": "examples/core_spells", "version": "^1.0.0"}]})
	assert_contains(_errs(_imp(lib).import_package(_hero({}, dup))), "dependencia_duplicada")
	_cleanup()


func test_import_requires_declared_dependency_and_existing_ability() -> void:
	var lib := _lib()
	_spells(lib)
	var undeclared := _char({"imports": [{"package": "examples/core_spells", "version": "*", "abilities": ["fireball"]}]})
	assert_contains(_errs(_imp(lib).import_package(_hero({}, "", undeclared))), "no esta declarada en manifest.dependencies")
	var mf := _mf("t/hero", "1.0.0", "character", {"dependencies": [{"id": "examples/core_spells", "version": "^1.0.0"}]})
	var ghost := _char({"imports": [{"package": "examples/core_spells", "version": "^1.0.0", "abilities": ["meteorito"]}]})
	assert_contains(_errs(_imp(lib).import_package(_hero({}, mf, ghost))), "no define la habilidad 'meteorito'")
	var good := _char({"imports": [{"package": "examples/core_spells", "version": "^1.0.0", "abilities": ["fireball"]}]})
	var rep := _imp(lib).import_package(_hero({"resources.json": JSON.stringify({"schema": "simhalla.resources/1", "resources": {"mana": {"initial": 50, "max": 50}}})}, mf, good))
	assert_true(rep.ok(), _errs(rep))
	assert_eq(rep.dependencies.size(), 1)
	var own_dup := _hero({"abilities.json": JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "fireball"}]}),
		"resources.json": JSON.stringify({"schema": "simhalla.resources/1", "resources": {"mana": {"initial": 50}}})}, _mf("t/hero2", "1.0.0", "character", {"dependencies": [{"id": "examples/core_spells", "version": "^1.0.0"}]}), good)
	assert_contains(_errs(_imp(lib).import_package(own_dup)), "duplicada")
	_cleanup()


func test_unused_dependency_warns_and_ai_ref_errors() -> void:
	var lib := _lib()
	assert_true(_imp(lib).import_package(PKG + "core_spells").ok())
	assert_true(_imp(lib).import_package(PKG + "basic_ai").ok())
	var mf := _mf("t/hero", "1.0.0", "character", {"dependencies": [{"id": "examples/core_spells", "version": "^1.0.0"}, {"id": "examples/basic_ai", "version": "^1.0.0"}]})
	var rep := _imp(lib).import_package(_hero({}, mf, _char({"ai_ref": {"package": "examples/basic_ai", "version": "^1.0.0", "strategy": "aggressive"}})))
	assert_true(rep.ok(), _errs(rep))
	assert_true(" ".join(rep.warnings).contains("no se usa"), "aviso de dependencia sin usar: %s" % str(rep.warnings))
	var bad := _imp(lib).import_package(_hero({}, mf, _char({"ai_ref": {"package": "examples/basic_ai", "version": "^1.0.0", "strategy": "inexistente"}})))
	assert_contains(_errs(bad), "no define la estrategia")
	var both := _imp(lib).import_package(_hero({"ai.json": JSON.stringify({"schema": "simhalla.ai/1", "ai": {"type": "passive"}})}, mf, _char({"ai_ref": {"package": "examples/basic_ai", "version": "^1.0.0", "strategy": "aggressive"}})))
	assert_contains(_errs(both), "a la vez")
	_cleanup()


func test_min_engine_version() -> void:
	var rep := _imp(_lib()).validate(_hero({}, _mf("t/hero", "1.0.0", "character", {"min_engine_version": "9.0.0"})))
	assert_contains(_errs(rep), "motor_incompatible")
	_cleanup()


# --- esquemas y semantica -----------------------------------------------------------------------

func test_schema_errors_name_file_and_path() -> void:
	var imp := _imp(_lib())
	var rep := imp.validate(_hero({}, "", _char({"stats": {"ATK": "mucho"}, "poder": 1})))
	var e := _errs(rep)
	assert_contains(e, "character.json: [esquema]")
	assert_contains(e, "stats.ATK")
	assert_contains(e, "propiedad desconocida 'poder'")
	var m := imp.validate(_hero({}, _mf("Mal/ID", "1.0")))
	assert_contains(_errs(m), "manifest.json: [esquema]")
	_cleanup()


func test_semantic_validation_like_in_combat() -> void:
	var imp := _imp(_lib())
	var cost_no_res := JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "cost": {"mana": 5}, "effects": [
		{"type": "damage", "components": [{"damage_type": "true", "formula": "1"}]}]}]})
	assert_contains(_errs(imp.validate(_hero({"abilities.json": cost_no_res}))), "recurso inexistente")
	var bad_formula := JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "effects": [
		{"type": "damage", "components": [{"damage_type": "true", "formula": "caster.ATK +"}]}]}]})
	assert_contains(_errs(imp.validate(_hero({"abilities.json": bad_formula}))), "formula")
	var bad_origin := JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "effects": [
		{"type": "heal", "formula": "world.secret"}]}]})
	assert_contains(_errs(imp.validate(_hero({"abilities.json": bad_origin}))), "origen de variable no permitido")
	var dup := JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "x"}, {"id": "x"}]})
	assert_contains(_errs(imp.validate(_hero({"abilities.json": dup}))), "repetido")
	var ghost_ai := JSON.stringify({"schema": "simhalla.ai/1", "ai": {"type": "priority_list", "rules": [{"ability": "nuke"}]}})
	assert_contains(_errs(imp.validate(_hero({"ai.json": ghost_ai}))), "inexistente")
	var no_hp := _char({"stats": {"HP": 0}})
	assert_contains(_errs(imp.validate(_hero({}, "", no_hp))), "HP")
	_cleanup()


func test_artifact_validation() -> void:
	var imp := _imp(_lib())
	var art := {"schema": "simhalla.artifact/1", "id": "espada", "modifiers": [{"stat": "ATK", "kind": "flat", "value": 10}]}
	assert_true(imp.validate(_hero({"artifact.json": JSON.stringify(art)})).ok())
	art["modifiers"] = [{"stat": "ATK", "kind": "magia", "value": 10}]
	assert_contains(_errs(imp.validate(_hero({"artifact.json": JSON.stringify(art)}))), "kind")
	var with_script := {"schema": "simhalla.artifact/1", "id": "x", "script": "OS.execute('ls')"}
	assert_contains(_errs(imp.validate(_hero({"artifact.json": JSON.stringify(with_script)}))), "propiedad desconocida 'script'")
	_cleanup()


func test_ai_package_rules() -> void:
	var imp := _imp(_lib())
	var good := _pkg({"manifest.json": _mf("t/ai", "1.0.0", "ai"), "ai.json": JSON.stringify({"schema": "simhalla.ai/1", "strategies": {"a": {"type": "passive"}}})})
	assert_true(imp.validate(good).ok())
	var inline := _pkg({"manifest.json": _mf("t/ai", "1.0.0", "ai"), "ai.json": JSON.stringify({"schema": "simhalla.ai/1", "ai": {"type": "passive"}})})
	assert_contains(_errs(imp.validate(inline)), "strategies")
	var bad := _pkg({"manifest.json": _mf("t/ai", "1.0.0", "ai"), "ai.json": JSON.stringify({"schema": "simhalla.ai/1", "strategies": {"a": {"type": "psiquica"}}})})
	assert_false(imp.validate(bad).ok())
	_cleanup()


# --- estructura de archivos --------------------------------------------------------------------

func test_file_set_rules() -> void:
	var imp := _imp(_lib())
	assert_contains(_errs(imp.validate(_hero({"notas.txt": "hola"}))), "archivo_desconocido")
	assert_contains(_errs(imp.validate(_hero({"scripts/hack.gd": "extends Node"}))), "nombre no valido")
	# En personajes effects/summons existen (fase 3) y se validan por esquema; en bibliotecas no.
	assert_contains(_errs(imp.validate(_hero({"effects.json": "{}"}))), "effects.json: [esquema]")
	assert_contains(_errs(imp.validate(_hero({"summons.json": "{}"}))), "summons.json: [esquema]")
	var libpkg := {"manifest.json": _mf("t/lib", "1.0.0", "abilities"), "abilities.json": JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "a"}]})}
	libpkg["effects.json"] = "{}"
	assert_contains(_errs(imp.validate(_pkg(libpkg))), "no_soportado")
	assert_contains(_errs(imp.validate(_pkg({"manifest.json": _mf()}))), "falta_archivo")
	assert_contains(_errs(imp.validate(_pkg({"character.json": _char()}))), "falta_manifiesto")
	assert_contains(_errs(imp.validate(_pkg({"manifest.json": _mf("t/lib", "1.0.0", "abilities"), "abilities.json": JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "a"}]}), "character.json": _char()}))), "archivo_desconocido")
	assert_contains(_errs(imp.validate("user://no/existe")), "no_encontrado")
	_cleanup()


func test_scripts_are_never_executed_on_import() -> void:
	# Un script malicioso se rechaza sin ejecutarse (no hay efectos secundarios).
	var marker := _dir() + "/pwned.txt"
	var evil := "extends Node\nfunc _init():\n\tvar f = FileAccess.open('%s', FileAccess.WRITE)\n\tf.store_string('x')\n" % marker
	var rep := _imp(_lib()).import_package(_hero({"scripts/evil.gd": evil}))
	assert_false(rep.ok())
	assert_false(FileAccess.file_exists(marker))
	_cleanup()


func test_json_errors() -> void:
	var imp := _imp(_lib())
	assert_contains(_errs(imp.validate(_hero({}, "", "{ \"schema\": "))), "character.json: [json]")
	assert_contains(_errs(imp.validate(_hero({}, "", "[1,2]"))), "la raiz debe ser un objeto")
	assert_contains(_errs(imp.validate(_hero({}, "", "\uFEFF" + _char()))), "BOM")
	var latin := PackedByteArray([0x7B, 0x22, 0xE9, 0x22, 0x3A, 0x31, 0x7D]) # {"é":1} en Latin-1 (no UTF-8)
	var p := _hero()
	var f := FileAccess.open(p.path_join("character.json"), FileAccess.WRITE)
	f.store_buffer(latin)
	f.close()
	assert_contains(_errs(imp.validate(p)), "UTF-8")
	_cleanup()


# --- seguridad de rutas y ZIP -----------------------------------------------------------------------

func _zip(entries: Dictionary) -> String:
	var path := _dir() + ".zip"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var zp := ZIPPacker.new()
	assert_eq(zp.open(path), OK)
	for name in entries:
		zp.start_file(name)
		var d: Variant = entries[name]
		zp.write_file(d if d is PackedByteArray else str(d).to_utf8_buffer())
		zp.close_file()
	zp.close()
	return path


func test_zip_import_equals_folder_import() -> void:
	var files := {"manifest.json": _mf(), "character.json": _char()}
	var lib_a := _lib()
	var ra := _imp(lib_a).import_package(_pkg(files))
	var lib_b := _lib()
	var rb := _imp(lib_b).import_package(_zip(files))
	assert_true(ra.ok() and rb.ok(), _errs(ra) + _errs(rb))
	assert_eq(ra.hash, rb.hash, "la huella no depende de carpeta o ZIP")
	assert_true(_imp(_lib()).import_package(_zip(files).replace(".zip", ".simpkg")) != null)
	_cleanup()


func test_zip_path_traversal_rejected() -> void:
	var imp := _imp(_lib())
	for evil in ["../evil.json", "/etc/passwd", "a/../../b.json", "a\\b.json", "C:/x.json", "a//b.json"]:
		var z := _zip({"manifest.json": _mf(), "character.json": _char(), evil: "{}"})
		var rep := imp.validate(z)
		assert_false(rep.ok(), "debe rechazar '%s'" % evil)
		assert_contains(_errs(rep), "path_traversal")
	_cleanup()


func test_zip_case_collision_and_duplicates() -> void:
	var z := _zip({"manifest.json": _mf(), "character.json": _char(), "Character.JSON": "{}"})
	assert_contains(_errs(_imp(_lib()).validate(z)), "colision")
	_cleanup()


func test_zip_bomb_and_size_limits() -> void:
	var imp := _imp(_lib())
	var zeros := PackedByteArray()
	zeros.resize(1_500_000)
	var bomb := _zip({"manifest.json": _mf(), "character.json": _char(), "assets/x.png": zeros})
	assert_contains(_errs(imp.validate(bomb)), "bomba_compresion")
	var big := PackedByteArray()
	big.resize(PackageSource.MAX_FILE_BYTES + 1)
	var huge := _zip({"manifest.json": _mf(), "character.json": _char(), "assets/x.png": big})
	assert_contains(_errs(imp.validate(huge)), "limite")
	var many := {"manifest.json": _mf(), "character.json": _char()}
	for i in 300:
		many["assets/a%d.png" % i] = "x"
	assert_contains(_errs(imp.validate(_zip(many))), "limite")
	_cleanup()


func test_corrupt_zip_rejected() -> void:
	var path := _dir() + ".zip"
	DirAccess.make_dir_recursive_absolute(path.get_base_dir())
	var f := FileAccess.open(path, FileAccess.WRITE)
	f.store_string("esto no es un zip")
	f.close()
	assert_contains(_errs(_imp(_lib()).validate(path)), "formato")
	var txt := _dir() + "/x.txt"
	DirAccess.make_dir_recursive_absolute(txt.get_base_dir())
	var g := FileAccess.open(txt, FileAccess.WRITE)
	g.store_string("x")
	g.close()
	assert_contains(_errs(_imp(_lib()).validate(txt)), "formato")
	_cleanup()


func test_directory_traversal_and_symlinks() -> void:
	var p := _hero()
	var outside := _dir() + "/outside.json"
	DirAccess.make_dir_recursive_absolute(outside.get_base_dir())
	var f := FileAccess.open(outside, FileAccess.WRITE)
	f.store_string("{}")
	f.close()
	var link := ProjectSettings.globalize_path(p.path_join("assets_link.json"))
	var rc := OS.execute("ln", ["-s", ProjectSettings.globalize_path(outside), link])
	if rc != 0:
		_cleanup()
		return # sin 'ln' en este sistema: no se puede probar
	var rep := _imp(_lib()).validate(p)
	assert_false(rep.ok())
	assert_contains(_errs(rep), "enlace_simbolico")
	_cleanup()


func test_path_checker() -> void:
	for bad in ["", "..", "../a", "a/../b", "/a", "a\\b", "a:b", "a//b", "./a", "a/."]:
		assert_ne(PackageSource.check_rel_path(bad), "", "ruta peligrosa: '%s'" % bad)
	for good in ["a.json", "assets/portrait.png", "scripts/x/y.gd"]:
		assert_eq(PackageSource.check_rel_path(good), "", good)


# --- assets ------------------------------------------------------------------------------------------

func test_assets_validation() -> void:
	var imp := _imp(_lib())
	var img := Image.create(4, 4, false, Image.FORMAT_RGBA8)
	var png := img.save_png_to_buffer()
	assert_true(imp.validate(_hero({"assets/portrait.png": png})).ok())
	assert_contains(_errs(imp.validate(_hero({"assets/portrait.png": "no soy png"}))), "asset")
	assert_contains(_errs(imp.validate(_hero({"assets/icon.svg": "<svg onload='x()'/>"}))), "extension no admitida")
	assert_contains(_errs(imp.validate(_hero({"assets/run.exe": "MZ"}))), "extension no admitida")
	var lib_pkg := _pkg({"manifest.json": _mf("t/lib", "1.0.0", "abilities"), "abilities.json": JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "a"}]}), "assets/p.png": png})
	assert_contains(_errs(imp.validate(lib_pkg)), "archivo_desconocido")
	_cleanup()


# --- huella ----------------------------------------------------------------------------------------------

func test_content_hash_is_order_independent_and_sensitive() -> void:
	var a := {"x.json": "1".to_utf8_buffer(), "y.json": "2".to_utf8_buffer()}
	var b := {"y.json": "2".to_utf8_buffer(), "x.json": "1".to_utf8_buffer()}
	assert_eq(PackageSource.content_hash(a), PackageSource.content_hash(b))
	b["x.json"] = "3".to_utf8_buffer()
	assert_ne(PackageSource.content_hash(a), PackageSource.content_hash(b))
	var renamed := {"x2.json": "1".to_utf8_buffer(), "y.json": "2".to_utf8_buffer()}
	assert_ne(PackageSource.content_hash(a), PackageSource.content_hash(renamed), "el nombre tambien cuenta")


# --- fase 3: estados propios, invocaciones, disparadores en paquetes -------------------------------------

func _p3_files(extra: Dictionary = {}) -> Dictionary:
	var abilities := {"schema": "simhalla.abilities/1", "abilities": [
		{"id": "hex", "targeting": "enemy", "cooldown": 2, "effects": [{"type": "apply_status", "status": "hexed", "chance": 0.7}]},
		{"id": "call_imp", "targeting": "self", "uses_per_combat": 1, "effects": [{"type": "summon", "template": "imp", "lifespan": 3}]},
		{"id": "thorns", "targeting": "enemy", "action_type": "reaction", "cooldown": 1,
		 "trigger": {"event": "damage_dealt", "when": {"event.target": {"eq": "self"}}, "target": "event_source"},
		 "effects": [{"type": "damage", "components": [{"damage_type": "true", "formula": "5"}]}]},
		{"id": "toughness", "passive": {"modifiers": [{"stat": "DEF", "kind": "flat", "value": 20}]}}]}
	var effects := {"schema": "simhalla.effects/1", "statuses": [
		{"id": "hexed", "tags": ["curse"], "duration": 3, "modifiers": [{"stat": "ATK", "kind": "pct_add", "value": -0.2}],
		 "periodic": [{"on": "turn_end", "effects": [{"type": "damage", "always_hit": true, "components": [{"damage_type": "true", "formula": "8"}]}]}]},
		{"id": "beast_form", "group": "form", "duration": 2, "form": {"add_abilities": [{"id": "claw", "targeting": "enemy", "effects": [{"type": "damage", "components": [{"damage_type": "physical", "formula": "caster.ATK"}]}]}]}}]}
	var summons := {"schema": "simhalla.summons/1", "summons": {"imp": {"name": "Diablillo", "stats": {"HP": 80, "ATK": 50, "SPD": 140}, "basic_attack": true}}}
	var files := {"manifest.json": _mf("t/summoner"), "character.json": _char({"stats": {"HP": 900, "ATK": 110}}),
		"abilities.json": JSON.stringify(abilities), "effects.json": JSON.stringify(effects), "summons.json": JSON.stringify(summons)}
	files.merge(extra, true)
	return files


func test_phase3_package_imports_and_fights() -> void:
	var lib := _lib()
	var rep := _imp(lib).import_package(_pkg(_p3_files()))
	assert_true(rep.ok(), _errs(rep))
	assert_true(_imp(lib).import_package(PKG + "iron_vanguard").ok())
	var cfg := {"seed": 4, "library": lib.root, "entities": [
		{"package": "t/summoner", "overrides": {"team": "A", "ai": {"type": "priority_list", "rules": [
			{"ability": "call_imp", "target": "self"}, {"ability": "hex", "target": "first_enemy"}, {"ability": "basic_attack", "target": "lowest_hp_enemy"}]}}},
		{"package": "examples/iron_vanguard", "overrides": {"team": "B"}}]}
	var out := DuelRunner.run(cfg)
	assert_true(out["ok"], str(out["errors"]))
	var eng: CombatEngine = out["engine"]
	var res: CombatResult = out["result"]
	assert_false(res.is_aborted(), str(res.error))
	assert_true(eng.log.of_type(EventTypes.SUMMON_CREATED).size() >= 1, "invocacion definida en summons.json")
	assert_true(eng.log.of_type(EventTypes.STATUS_APPLIED).size() >= 1, "estado propio definido en effects.json")
	assert_almost(eng.get_entity("t/summoner").stats.get_value("DEF"), 120.0, 1e-9, "pasiva importada")
	assert_eq(DuelRunner.run(cfg)["result"].log_hash, res.log_hash, "reproducible")
	_cleanup()


func test_phase3_package_validation_errors() -> void:
	var imp := _imp(_lib())
	var abil_bad_status := JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "targeting": "enemy", "effects": [{"type": "apply_status", "status": "fantasma"}]}]})
	assert_contains(_errs(imp.validate(_pkg(_p3_files({"abilities.json": abil_bad_status})))), "estado inexistente 'fantasma'")
	var abil_bad_tmpl := JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "targeting": "self", "effects": [{"type": "summon", "template": "dragon"}]}]})
	assert_contains(_errs(imp.validate(_pkg(_p3_files({"abilities.json": abil_bad_tmpl})))), "plantilla inexistente 'dragon'")
	var bad_effects := JSON.stringify({"schema": "simhalla.effects/1", "statuses": [{"id": "s1", "stacking": {"policy": "magia"}}]})
	assert_false(imp.validate(_pkg(_p3_files({"effects.json": bad_effects}))).ok())
	var unknown_key := JSON.stringify({"schema": "simhalla.effects/1", "statuses": [{"id": "s1", "poder": 9}]})
	assert_contains(_errs(imp.validate(_pkg(_p3_files({"effects.json": unknown_key})))), "propiedad desconocida 'poder'")
	var bad_trigger := JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "trigger": {"when": {}}}]})
	assert_contains(_errs(imp.validate(_pkg(_p3_files({"abilities.json": bad_trigger})))), "event")
	var bad_tmpl := JSON.stringify({"schema": "simhalla.summons/1", "summons": {"imp": {"stats": {"HP": 0}}}})
	assert_contains(_errs(imp.validate(_pkg(_p3_files({"summons.json": bad_tmpl})))), "summons.imp")
	var evil_op := JSON.stringify({"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "targeting": "enemy", "effects": [{"type": "exec", "cmd": "rm -rf /"}]}]})
	assert_false(imp.validate(_pkg(_p3_files({"abilities.json": evil_op}))).ok())
	assert_true(imp.validate(_pkg(_p3_files())).ok())
	_cleanup()
