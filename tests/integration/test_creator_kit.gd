extends TestCase
## Kit para IAs creadoras de personajes: plantillas validas y jugables, herramienta de comprobacion (CharacterCheck) y una guia que no se
## desincroniza de los esquemas publicos (cada JSON de la guia valida y se mencionan todos los valores permitidos).

const TMP := "user://_tests_kit"
const KIT := "res://docs/AI_CREATOR_KIT.md"
const SCHEMA_OF := {"manifest": "manifest.schema.json", "character": "character.schema.json", "abilities": "abilities.schema.json", "resources": "resources.schema.json",
	"ai": "ai.schema.json", "effects": "effects.schema.json", "summons": "summons.schema.json", "artifact": "artifact.schema.json"}


func _write(dir: String, files: Dictionary) -> String:
	var d := "%s/%s_%d" % [TMP, dir, Time.get_ticks_usec()]
	DirAccess.make_dir_recursive_absolute(d)
	for n in files:
		var f := FileAccess.open(d.path_join(n), FileAccess.WRITE)
		f.store_string(files[n] if files[n] is String else JSON.stringify(files[n]))
		f.close()
	return d


func _idle_pkg(extra_ai: Array = []) -> String:
	return _write("idle", {
		"manifest.json": {"schema": "simhalla.manifest/1", "id": "test/idle", "version": "1.0.0", "type": "character", "name": "Ocioso"},
		"character.json": {"schema": "simhalla.character/1", "name": "Ocioso", "stats": {"HP": 900, "ATK": 120}, "basic_attack": true},
		"abilities.json": {"schema": "simhalla.abilities/1", "abilities": [{"id": "never", "name": "Nunca", "action_type": "main", "targeting": "enemy",
			"effects": [{"type": "damage", "components": [{"damage_type": "physical", "formula": "caster.ATK * 3"}]}]}]},
		"ai.json": {"schema": "simhalla.ai/1", "ai": {"type": "priority_list", "rules": [{"ability": "basic_attack", "target": "first_enemy"}]}}})


# --- plantillas ------------------------------------------------------------------------------------------------------------

func test_every_template_is_valid_playable_and_does_not_abort() -> void:
	for n in CharacterCheck.TEMPLATE_CHARS:
		var r := CharacterCheck.run("res://content/templates/" + n, {"reps": 2, "seed": 3})
		assert_true(r["ok"], "%s: %s" % [n, str(r["errors"])])
		assert_eq(r["package"]["id"], "templates/" + n)
		assert_eq(r["duels"]["aborted"], 0, "%s: duelos abortados" % n)
		assert_true(r["duels"]["games"] > 0, n)
		assert_true(r["cost"]["creation_cost"] > 0.0, n)
		for d in r["diagnostics"]:
			assert_false(str(d).begins_with("ERROR TECNICO"), "%s: %s" % [n, d])
		assert_false(str(r["diagnostics"]).contains("NO se uso"), "%s: habilidad sin usar: %s" % [n, str(r["diagnostics"])])
	for n in CharacterCheck.TEMPLATE_LIBS:
		var r := CharacterCheck.run("res://content/templates/" + n)
		assert_true(r["ok"], "%s: %s" % [n, str(r["errors"])])
		assert_eq(r["duels"], {}, "las bibliotecas no se enfrentan")
		assert_contains(str(r["diagnostics"]), "biblioteca")


func test_template_library_dependencies_are_declared_and_required() -> void:
	var m: Dictionary = EntityFactory.load_json("res://content/templates/character_with_libraries/manifest.json")
	assert_eq((m["dependencies"] as Array).map(func(d): return d["id"]), ["templates/library_abilities", "templates/library_ai"])
	var c: Dictionary = EntityFactory.load_json("res://content/templates/character_with_libraries/character.json")
	assert_eq(c["imports"][0]["package"], "templates/library_abilities")
	assert_eq(c["ai_ref"]["strategy"], "bruiser")


# --- herramienta de comprobacion -------------------------------------------------------------------------------------------------

func test_invalid_package_is_rejected_with_actionable_errors() -> void:
	var p := _write("bad", {
		"manifest.json": {"schema": "simhalla.manifest/1", "id": "test/bad", "version": "1.0.0", "type": "character", "name": "Malo"},
		"character.json": {"schema": "simhalla.character/1", "name": "Malo", "abilities": [{"id": "x"}], "poder_oculto": true}})
	var r := CharacterCheck.run(p)
	assert_false(r["ok"])
	assert_eq(r["stage"], "import")
	var txt := "; ".join(r["errors"])
	assert_contains(txt, "propiedad desconocida 'abilities'")
	assert_contains(txt, "permitidas", "el error lista los campos permitidos")
	assert_contains(CharacterCheck.to_markdown(r), "RECHAZADO")
	assert_eq(r["duels"], {})
	ContentLibrary._remove_tree(TMP)


func test_unused_ability_is_reported_and_results_are_deterministic() -> void:
	var p := _idle_pkg()
	var a := CharacterCheck.run(p, {"reps": 2, "seed": 5})
	assert_true(a["ok"], str(a["errors"]))
	assert_contains("; ".join(a["diagnostics"]), "'never' NO se uso")
	var b := CharacterCheck.run(p, {"reps": 2, "seed": 5})
	assert_eq(a["duels"]["fingerprint"], b["duels"]["fingerprint"], "misma semilla, mismo resultado")
	assert_eq(JSON.stringify(a["duels"]["opponents"]), JSON.stringify(b["duels"]["opponents"]))
	var c := CharacterCheck.run(p, {"reps": 2, "seed": 6})
	assert_ne(a["duels"]["fingerprint"], c["duels"]["fingerprint"])
	assert_true(JSON.stringify(a).length() > 100, "el resultado es serializable a JSON")
	var md := CharacterCheck.to_markdown(a)
	assert_contains(md, "Diagnostico")
	assert_contains(md, "basic_attack")
	ContentLibrary._remove_tree(TMP)


func test_options_vs_budget_and_deps() -> void:
	var p := _idle_pkg()
	var vs := CharacterCheck.run(p, {"reps": 2, "vs": ["pkg:examples/iron_vanguard"]})
	assert_true(vs["ok"], str(vs["errors"]))
	assert_eq(vs["duels"]["opponents"].size(), 1)
	assert_eq(vs["duels"]["opponents"][0]["id"], "examples/iron_vanguard")
	assert_eq(vs["duels"]["opponents"][0]["games"], 2, "2 repeticiones, el personaje como equipo A")
	var small := CharacterCheck.run(p, {"reps": 2, "budget": "small", "vs": ["examples/iron_vanguard"]})
	assert_eq(small["cost"]["budget_id"], "small")
	assert_eq(small["cost"]["budget_points"], 200.0)
	var bad_budget := CharacterCheck.run(p, {"budget": "no_existe"})
	assert_false(bad_budget["ok"])
	# dependencia propia: un personaje que usa una biblioteca del creador
	var lib := _write("mylib", {
		"manifest.json": {"schema": "simhalla.manifest/1", "id": "test/mylib", "version": "1.0.0", "type": "abilities", "name": "Mi biblioteca"},
		"abilities.json": {"schema": "simhalla.abilities/1", "abilities": [{"id": "slam", "name": "Slam", "action_type": "main", "targeting": "enemy", "cooldown": 2,
			"effects": [{"type": "damage", "components": [{"damage_type": "physical", "formula": "caster.ATK * 1.8"}]}]}]}})
	var hero := _write("hero", {
		"manifest.json": {"schema": "simhalla.manifest/1", "id": "test/hero", "version": "1.0.0", "type": "character", "name": "Heroe",
			"dependencies": [{"id": "test/mylib", "version": "^1.0.0"}]},
		"character.json": {"schema": "simhalla.character/1", "name": "Heroe", "stats": {"HP": 1000, "ATK": 130}, "basic_attack": true,
			"imports": [{"package": "test/mylib", "version": "^1.0.0", "abilities": ["slam"]}]},
		"ai.json": {"schema": "simhalla.ai/1", "ai": {"type": "priority_list", "rules": [{"ability": "slam", "target": "lowest_hp_enemy"}, {"ability": "basic_attack", "target": "lowest_hp_enemy"}]}}})
	var without := CharacterCheck.run(hero, {"reps": 2})
	assert_false(without["ok"], "sin --deps la dependencia no se encuentra")
	assert_contains("; ".join(without["errors"]), "test/mylib")
	var with_dep := CharacterCheck.run(hero, {"reps": 2, "deps": [lib]})
	assert_true(with_dep["ok"], str(with_dep["errors"]))
	assert_true(with_dep["duels"]["abilities"].any(func(a): return a["id"] == "slam" and a["uses"] > 0))
	var broken_dep := CharacterCheck.run(hero, {"deps": [_write("empty", {})]})
	assert_false(broken_dep["ok"])
	assert_eq(broken_dep["stage"], "deps")
	ContentLibrary._remove_tree(TMP)


func test_check_never_touches_the_users_library() -> void:
	var before := DirAccess.dir_exists_absolute("user://simhalla/library")
	var r := CharacterCheck.run("res://content/templates/character_minimal", {"reps": 2, "vs": ["examples/iron_vanguard"]})
	assert_true(r["ok"])
	assert_eq(DirAccess.dir_exists_absolute("user://simhalla/library"), before)
	assert_false(DirAccess.dir_exists_absolute("user://_character_check") and not DirAccess.get_directories_at("user://_character_check").is_empty(), "limpia su biblioteca temporal")


# --- la guia no se desincroniza ----------------------------------------------------------------------------------------------------

func _kit() -> String:
	return FileAccess.get_file_as_string(KIT)


func test_every_json_block_in_the_guide_is_valid_and_matches_its_public_schema() -> void:
	var text := _kit()
	var rx := RegEx.create_from_string("```json\\n([\\s\\S]*?)\\n```")
	var blocks := rx.search_all(text)
	assert_true(blocks.size() >= 5, "la guia lleva ejemplos JSON (%d)" % blocks.size())
	var checked := 0
	for m in blocks:
		var j := JSON.new()
		assert_eq(j.parse(m.get_string(1)), OK, "JSON invalido en la guia: %s" % m.get_string(1).substr(0, 60))
		var d: Variant = j.data
		if d is Dictionary and str(d.get("schema", "")).begins_with("simhalla."):
			var fam := SchemaMigrator.parse_id(d["schema"])["family"] as String
			if SCHEMA_OF.has(fam):
				var errs := SchemaValidator.new().validate(SCHEMA_OF[fam], d)
				assert_eq(errs, [], "el ejemplo '%s' de la guia no cumple su esquema" % fam)
				checked += 1
	assert_true(checked >= 5, "al menos 5 ejemplos validados contra esquemas (%d)" % checked)


func test_guide_mentions_every_value_the_public_schema_allows() -> void:
	var text := _kit()
	var common: Dictionary = EntityFactory.load_json("res://schemas/common.schema.json")
	var defs: Dictionary = common["definitions"]
	var want := {
		"efecto": defs["effect"]["properties"]["type"]["enum"],
		"on": defs["effect"]["properties"]["on"]["enum"],
		"action_type": defs["ability"]["properties"]["action_type"]["enum"],
		"targeting": defs["ability"]["properties"]["targeting"]["enum"],
		"ia": defs["ai_config"]["properties"]["type"]["enum"],
		"politica": defs["status"]["properties"]["stacking"]["properties"]["policy"]["enum"],
		"unidad": defs["duration"]["properties"]["unit"]["enum"],
		"modificador": defs["modifier"]["properties"]["kind"]["enum"],
		"objetivo IA": defs["ai_rule"]["properties"]["target"]["enum"],
		"daño": defs["damage_component"]["properties"]["damage_type"]["enum"],
		"nodo": defs["ai_bt_node"]["properties"]["type"]["enum"],
	}
	for k in want:
		for v in want[k]:
			assert_contains(text, str(v), "la guia no menciona %s '%s'" % [k, v])


func test_guide_references_existing_files_templates_and_tools() -> void:
	var text := _kit()
	for n in CharacterCheck.TEMPLATE_CHARS + CharacterCheck.TEMPLATE_LIBS:
		assert_contains(text, n, "la guia no menciona la plantilla %s" % n)
		assert_true(FileAccess.file_exists("res://content/templates/%s/manifest.json" % n), n)
	for tool in ["tools/character_check.gd", "tools/package_tool.gd", "tools/run_duel.gd"]:
		assert_contains(text, tool)
		assert_true(FileAccess.file_exists("res://" + tool), tool)
	for doc in ["docs/PACKAGES.md", "docs/ABILITY_REFERENCE.md", "docs/AI_REFERENCE.md", "docs/EVENTS.md", "docs/COMBAT_RULES.md", "docs/BALANCE_RULES.md", "docs/SCRIPTING_API.md"]:
		assert_contains(text, doc)
		assert_true(FileAccess.file_exists("res://" + doc), doc)
	var cfg := ConfigFile.new()
	assert_eq(cfg.load("res://export_presets.cfg"), OK)
	for sec in cfg.get_sections():
		if not sec.ends_with(".options"):
			assert_contains(str(cfg.get_value(sec, "include_filter")), "*.json", "las plantillas (json) viajan en los exportados")
