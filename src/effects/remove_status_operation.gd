class_name RemoveStatusOperation
extends EffectOperation
## Disipar/eliminar estados: {"type":"remove_status","status":"id" | "tags":["poison"] | "beneficial":false,
##  "count":2,"force":false}. Respeta `dispellable` salvo force.

func type_id() -> String:
	return "remove_status"


func allowed_keys() -> Array:
	return ["type", "status", "tags", "beneficial", "count", "force"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if not (effect.has("status") or effect.has("tags") or effect.has("beneficial")):
		errs.append("remove_status: indique 'status', 'tags' o 'beneficial'")
	if effect.has("tags") and not (effect["tags"] is Array):
		errs.append("remove_status.tags debe ser una lista")
	if effect.has("count") and (not (effect["count"] is float or effect["count"] is int) or int(effect["count"]) < 1):
		errs.append("remove_status.count debe ser un entero >= 1")
	errs.append_array(check_types(effect, ["beneficial", "force"], [], "remove_status"))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	for target in ctx.targets:
		ctx.engine.status_service.dispel(target, effect, "dispelled", ctx.cause_id)
