extends TestCase
## Validador de esquemas publicos: errores claros con archivo/ruta.

var sv := SchemaValidator.new()


func _manifest(over: Dictionary = {}) -> Dictionary:
	var m := {"schema": "simhalla.manifest/1", "id": "ns/pkg", "version": "1.0.0", "type": "character", "name": "X"}
	m.merge(over, true)
	return m


func _errs(schema: String, data: Variant) -> String:
	return " | ".join(sv.validate(schema, data))


func test_valid_manifest() -> void:
	assert_eq(sv.validate("manifest.schema.json", _manifest()), [])


func test_required_and_unknown_property() -> void:
	var m := _manifest()
	m.erase("name")
	assert_contains(_errs("manifest.schema.json", m), "falta la propiedad obligatoria 'name'")
	assert_contains(_errs("manifest.schema.json", _manifest({"poder": 9000})), "propiedad desconocida 'poder'")


func test_pattern_enum_const_type() -> void:
	assert_contains(_errs("manifest.schema.json", _manifest({"id": "Mayusculas/Mal"})), "id")
	assert_contains(_errs("manifest.schema.json", _manifest({"id": "sinnamespace"})), "formato")
	assert_contains(_errs("manifest.schema.json", _manifest({"version": "1.0"})), "version")
	assert_contains(_errs("manifest.schema.json", _manifest({"type": "villano"})), "no permitido")
	assert_contains(_errs("manifest.schema.json", _manifest({"schema": "simhalla.manifest/2"})), "debe valer")
	assert_contains(_errs("manifest.schema.json", _manifest({"name": 5})), "se esperaba string")


func test_nested_paths_in_errors() -> void:
	var ch := {"schema": "simhalla.character/1", "name": "X", "stats": {"ATK": "mucho", "DEF": 5}}
	assert_contains(_errs("character.schema.json", ch), "stats.ATK")
	var ab := {"schema": "simhalla.abilities/1", "abilities": [{"id": "ok"}, {"id": "Mal Id"}, {"id": "x", "effects": [{"type": "teleport"}]}]}
	var e := _errs("abilities.schema.json", ab)
	assert_contains(e, "abilities[1].id")
	assert_contains(e, "abilities[2].effects[0].type")


func test_ref_across_files_and_ranges() -> void:
	var ab := {"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "effects": [{"type": "damage", "components": [
		{"damage_type": "true", "formula": "1", "pen_pct": 1.5}]}]}]}
	assert_contains(_errs("abilities.schema.json", ab), "pen_pct")
	assert_contains(_errs("abilities.schema.json", ab), "maximo")
	var ab2 := {"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "target_count": 0}]}
	assert_contains(_errs("abilities.schema.json", ab2), "minimo")


func test_array_bounds_and_integer() -> void:
	var ab := {"schema": "simhalla.abilities/1", "abilities": [{"id": "x", "target_count": 1.5}]}
	assert_contains(_errs("abilities.schema.json", ab), "integer")
	var ch := {"schema": "simhalla.character/1", "name": "X", "imports": [{"package": "a/b", "version": "*", "abilities": []}]}
	assert_contains(_errs("character.schema.json", ch), "al menos")


func test_root_type_checked() -> void:
	assert_contains(_errs("manifest.schema.json", [1, 2]), "se esperaba object")


func test_all_public_schemas_load() -> void:
	for f in ["common", "manifest", "character", "abilities", "resources", "ai", "artifact"]:
		assert_false(sv.load_schema(f + ".schema.json").is_empty(), f)
