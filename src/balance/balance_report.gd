class_name BalanceReport
extends RefCounted
## Resultado trazable de valorar un PJ: desglose por componente con regla, hechos, formula y origen.
##
## creation_cost = sum(items contados)  [= stat_adjustments + componentes comprados + otros costes - creditos]
## remaining     = budget - creation_cost
## Cada item lleva la regla del perfil aplicada, los hechos de entrada y el importe. Los componentes que el perfil
## no puede valorar se listan en `unevaluable` SIN precio inventado. Los informes de perfiles ilustrativos se
## etiquetan como PRUEBA. No se afirma que igualdad de PC implique igualdad de poder (PROJECT.md 9.3).

var entity_id: String = ""
var profile_id: String = ""
var profile_version: String = ""
var illustrative: bool = true
var mode: String = "free"
var budget_id: String = ""
var budget_points: float = -1.0 ## -1 = sin presupuesto
var items: Array = [] ## [{id, kind, origin, rule, parent, counted, credit, amount, facts, formula, unevaluable, reason}]
var unevaluable: Array = [] ## [{id, reason}]
var gross: float = 0.0
var credits_raw: float = 0.0
var credits_applied: float = 0.0
var creation_cost: float = 0.0
var remaining: float = 0.0
var errors: Array = [] ## bloquean segun el modo
var warnings: Array = []
var technical_errors: Array = [] ## contenido tecnicamente invalido (no se valora)


func within_budget() -> bool:
	return budget_points < 0.0 or creation_cost <= budget_points


func evaluable() -> bool:
	return unevaluable.is_empty()


## Valido segun el modo: libre = solo validez tecnica; reglamentado = ademas presupuesto y evaluabilidad.
func valid() -> bool:
	return technical_errors.is_empty() and errors.is_empty()


const DISCLAIMER := "Igualdad de PC no implica igualdad de poder: la valoracion es estructural y determinista; la evaluacion empirica (simulaciones) es independiente."


func labels() -> Array:
	return ["PRUEBA: perfil ilustrativo, cifras no definitivas"] if illustrative else []


func to_dict() -> Dictionary:
	return {
		"entity": entity_id, "profile": {"id": profile_id, "version": profile_version, "illustrative": illustrative},
		"labels": labels(), "note": DISCLAIMER, "mode": mode, "budget": {"id": budget_id, "points": budget_points},
		"gross": gross, "credits_raw": credits_raw, "credits_applied": credits_applied, "creation_cost": creation_cost,
		"remaining": remaining, "within_budget": within_budget(), "evaluable": evaluable(), "valid": valid(),
		"items": items, "unevaluable": unevaluable, "errors": errors, "warnings": warnings, "technical_errors": technical_errors,
	}


func to_markdown() -> String:
	var s := "# Valoracion de creacion: %s\n\n" % entity_id
	for l in labels():
		s += "> **%s**\n\n" % l
	s += "Perfil `%s@%s` · modo **%s**" % [profile_id, profile_version, mode]
	if budget_points >= 0.0:
		s += " · presupuesto `%s` = %s PC" % [budget_id, _n(budget_points)]
	s += "\n\n| Componente | Tipo | Origen | Regla | Importe |\n|---|---|---|---|---:|\n"
	for it in items:
		var amount_txt: String = "—" if bool(it.get("unevaluable", false)) else _n(float(it["amount"]))
		if not bool(it["counted"]):
			amount_txt = "(%s)" % amount_txt
		s += "| %s%s | %s | %s | %s | %s |\n" % ["  ".repeat(1 if str(it.get("parent", "")) != "" else 0), it["id"], it["kind"], it["origin"], it["rule"], amount_txt]
	s += "\n_%s_\n" % DISCLAIMER
	s += "\nBruto: %s · Creditos aplicados: %s (brutos %s) · **Coste de creacion: %s**" % [_n(gross), _n(credits_applied), _n(credits_raw), _n(creation_cost)]
	if budget_points >= 0.0:
		s += " · Restante: %s" % _n(remaining)
	s += "\n"
	if not unevaluable.is_empty():
		s += "\n## No evaluables (sin precio)\n"
		for u in unevaluable:
			s += "- `%s`: %s\n" % [u["id"], u["reason"]]
	for e in errors:
		s += "\n- ERROR: %s" % str(e)
	for w in warnings:
		s += "\n- Aviso: %s" % str(w)
	return s + "\n"


static func _n(v: float) -> String:
	return str(int(v)) if floorf(v) == v else "%.2f" % v
