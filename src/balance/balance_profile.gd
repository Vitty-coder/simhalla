class_name BalanceProfile
extends RefCounted
## Perfil de equilibrio: estadisticas base gratuitas (fase 1) + modelo de costes,
## presupuestos y redondeo (fase 6, ver CostRules y BalanceEvaluator).
##
## Separado del reglamento: define con que valores parte todo PJ y como se valoran
## las capacidades. Todo es DATO externo y versionado (nunca incrustado en el motor).
## Los perfiles marcados `illustrative` son de prueba: sus cifras no son un equilibrio
## definitivo y los informes los etiquetan como tales.
##
## Representacion interna: probabilidades y multiplicadores normalizados
## (ACC 1.0 = 100 %, CRIT_DMG 1.5 = x1.5).

var id: String = ""
var version: String = ""
var illustrative: bool = true
var base_stats: Dictionary = {}
var description: String = ""
## Modelo de costes (fase 6): ver CostRules. Vacio = perfil sin costes (solo estadisticas base).
var costs: Dictionary = {}
var budgets: Dictionary = {} ## {id: {points, label}}
var default_budget: String = ""
var rounding: Dictionary = {"mode": "round", "decimals": 0}
var credit_cap: Dictionary = {} ## {fraction_of_gross}: limite a las devoluciones por desventajas
var errors: Array[String] = []

const TOP_KEYS := ["schema", "id", "version", "illustrative", "description", "base_stats", "costs", "budgets", "default_budget", "rounding", "credit_cap"]


static func from_dict(d: Dictionary) -> BalanceProfile:
	var p := BalanceProfile.new()
	p.id = str(d.get("id", ""))
	p.version = str(d.get("version", ""))
	p.illustrative = bool(d.get("illustrative", true))
	p.description = str(d.get("description", ""))
	for k in d:
		if not TOP_KEYS.has(str(k)):
			p.errors.append("perfil: propiedad desconocida '%s' (permitidas: %s)" % [str(k), ", ".join(TOP_KEYS)])
	p._load_balance(d)
	var bs: Variant = d.get("base_stats", null)
	if p.id == "":
		p.errors.append("perfil sin 'id'")
	if not (bs is Dictionary) or (bs as Dictionary).is_empty():
		p.errors.append("perfil sin 'base_stats'")
	else:
		for k in bs:
			if not (bs[k] is float or bs[k] is int):
				p.errors.append("base_stats.%s debe ser numerico" % str(k))
			else:
				p.base_stats[str(k)] = float(bs[k])
	return p


func _load_balance(d: Dictionary) -> void:
	if d.has("costs"):
		var cerrs := CostRules.validate(d["costs"])
		errors.append_array(cerrs)
		if cerrs.is_empty():
			costs = (d["costs"] as Dictionary).duplicate(true)
	if d.has("budgets"):
		var b: Variant = d["budgets"]
		if not (b is Dictionary) or (b as Dictionary).is_empty():
			errors.append("budgets debe ser un objeto {id: {points}} no vacio")
		else:
			for k in b:
				var pts: Variant = b[k].get("points", null) if b[k] is Dictionary else null
				if not (pts is float or pts is int) or float(pts) <= 0.0:
					errors.append("budgets.%s.points debe ser un numero > 0" % str(k))
				else:
					budgets[str(k)] = {"points": float(pts), "label": str(b[k].get("label", ""))}
	default_budget = str(d.get("default_budget", ""))
	if default_budget != "" and not budgets.has(default_budget):
		errors.append("default_budget '%s' no esta en budgets" % default_budget)
	if d.has("rounding"):
		var r: Variant = d["rounding"]
		if not (r is Dictionary) or not Rounding.MODES.has(str(r.get("mode", "round"))) or int(r.get("decimals", 0)) < 0 or int(r.get("decimals", 0)) > 6:
			errors.append("rounding: use {mode: %s, decimals: 0..6}" % "|".join(Rounding.MODES))
		else:
			rounding = {"mode": str(r.get("mode", "round")), "decimals": int(r.get("decimals", 0))}
	if d.has("credit_cap"):
		var c: Variant = d["credit_cap"]
		var fr: Variant = c.get("fraction_of_gross", null) if c is Dictionary else null
		if not (fr is float or fr is int) or float(fr) < 0.0 or float(fr) > 1.0:
			errors.append("credit_cap: use {fraction_of_gross: 0..1}")
		else:
			credit_cap = {"fraction_of_gross": float(fr)}


## Representacion JSON del perfil (inversa de from_dict): para guardar instantaneas inline.
func to_dict() -> Dictionary:
	var d := {"schema": "simhalla.balance/1", "id": id, "version": version, "illustrative": illustrative, "description": description, "base_stats": base_stats.duplicate()}
	if has_costs():
		d["costs"] = costs.duplicate(true)
	if not budgets.is_empty():
		d["budgets"] = budgets.duplicate(true)
	if default_budget != "":
		d["default_budget"] = default_budget
	d["rounding"] = rounding.duplicate()
	if not credit_cap.is_empty():
		d["credit_cap"] = credit_cap.duplicate()
	return d


## ¿Define un modelo de costes? (los perfiles tecnicos solo traen estadisticas base)
func has_costs() -> bool:
	return not costs.is_empty()


static func from_file(path: String) -> BalanceProfile:
	var f := FileAccess.open(path, FileAccess.READ)
	if f != null:
		var parsed: Variant = JSON.parse_string(f.get_as_text())
		if parsed is Dictionary:
			return from_dict(parsed)
	var p := BalanceProfile.new()
	p.errors.append("no se pudo leer un objeto JSON de '%s'" % path)
	return p


## Perfil minimo por defecto (valores de referencia provisionales del PROJECT.md).
static func default_profile() -> BalanceProfile:
	return from_dict({
		"id": "technical_profile", "version": "0.1.0", "illustrative": true,
		"base_stats": {
			"HP": 1000, "ATK": 100, "MAG": 100, "DEF": 100, "RES": 100, "SPD": 100,
			"ACC": 1.0, "EVA": 0.10, "CRIT": 0.10, "CRIT_DMG": 1.5, "HEAL_REC": 1.0,
		},
	})


func is_valid() -> bool:
	return errors.is_empty()


func apply_base_stats(stats: StatSet) -> void:
	for k in base_stats:
		stats.set_base(k, base_stats[k])
