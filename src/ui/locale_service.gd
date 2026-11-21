class_name LocaleService
extends RefCounted
## Localizacion de la interfaz mediante RECURSOS (`content/locale/<idioma>.json`), no con ids cambiantes en los archivos de
## contenido: la interfaz usa claves estables (`nav.library`) y cada idioma aporta su texto. Español inicial; los IDs tecnicos
## del contenido se mantienen en ingles. Se registra una `Translation` por idioma en el `TranslationServer` (asi `tr()` de los
## controles tambien funciona). Clave ausente en un idioma => se usa el español; ausente en todos => la propia clave.

const LOCALES := ["es", "en"]
const DIR := "res://content/locale/"
const FALLBACK := "es"

static var _tables: Dictionary = {}
static var _current: String = "es"
static var missing: Dictionary = {}


## Carga (una vez) todas las tablas y registra las traducciones. Devuelve errores.
static func load_all() -> Array:
	var errs: Array = []
	if not _tables.is_empty():
		return errs
	for loc in LOCALES:
		var parsed: Variant = JSON.parse_string(FileAccess.get_file_as_string(DIR + loc + ".json"))
		if not (parsed is Dictionary) or not (parsed.get("strings", null) is Dictionary):
			errs.append("locale %s: archivo ilegible" % loc)
			continue
		_tables[loc] = parsed["strings"]
		var tr_res := Translation.new()
		tr_res.locale = loc
		for k in parsed["strings"]:
			tr_res.add_message(StringName(k), str(parsed["strings"][k]))
		TranslationServer.add_translation(tr_res)
	return errs


static func set_locale(loc: String) -> bool:
	load_all()
	if not LOCALES.has(loc):
		return false
	_current = loc
	TranslationServer.set_locale(loc)
	return true


static func current() -> String:
	return _current


static func keys(loc: String = FALLBACK) -> Array:
	load_all()
	return (_tables.get(loc, {}) as Dictionary).keys()


## Texto de `key` (con marcadores `{0}`, `{1}`... sustituidos por `args`).
static func t(key: String, args: Array = []) -> String:
	load_all()
	var s: String
	if (_tables.get(_current, {}) as Dictionary).has(key):
		s = str(_tables[_current][key])
	elif (_tables.get(FALLBACK, {}) as Dictionary).has(key):
		s = str(_tables[FALLBACK][key])
	else:
		missing[key] = true
		return key
	for i in args.size():
		s = s.replace("{%d}" % i, str(args[i]))
	return s
