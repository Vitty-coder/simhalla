class_name InvertStatusOperation
extends EffectOperation
## {"type":"invert_status","status":"id" | "tags":[..] | "beneficial":bool,"count":n}
## Invierte los estados seleccionados del objetivo: sus modificadores (flat/pct_add se
## niegan; mult se invierte) y sus efectos periodicos (dano <-> curacion). Un buff se
## convierte en debuff (y para el filtro `beneficial` cuenta al reves). Repetir la
## operacion lo deshace. No invierte defensas ni banderas (provisional, D-052).

func type_id() -> String:
	return "invert_status"


func allowed_keys() -> Array:
	return ["type", "status", "tags", "beneficial", "count"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if not (effect.has("status") or effect.has("tags") or effect.has("beneficial")):
		errs.append("invert_status: indique 'status', 'tags' o 'beneficial'")
	if effect.has("count") and (not (effect["count"] is float or effect["count"] is int) or int(effect["count"]) < 1):
		errs.append("invert_status.count debe ser un entero >= 1")
	errs.append_array(check_types(effect, ["beneficial"], [], "invert_status"))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var limit: int = int(effect.get("count", 9999))
	for t in ctx.targets:
		var n := 0
		for st in ctx.engine.status_service.matching(t, effect):
			if n >= limit:
				break
			ctx.engine.status_service.invert(st, ctx.cause_id)
			n += 1
