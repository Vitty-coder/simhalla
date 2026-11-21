class_name EmitEventOperation
extends EffectOperation
## Evento de usuario autorizado: {"type":"emit_event","name":"combo_ready","data":{"n":3}}
## Emite `user.<name>` (INFO) con datos escalares (max 16 claves). Las habilidades
## disparadas pueden suscribirse a `user.<name>`. Los nombres de evento propios del
## motor no se pueden emitir desde contenido.

func type_id() -> String:
	return "emit_event"


func allowed_keys() -> Array:
	return ["type", "name", "data"]


func validate(effect: Dictionary) -> Array:
	var errs: Array = []
	if not (effect.get("name", null) is String) or not RegEx.create_from_string("^[a-z][a-z0-9_]{0,31}$").search(str(effect.get("name", ""))):
		errs.append("emit_event.name debe ser un identificador en minusculas")
	if effect.has("data"):
		var d: Variant = effect["data"]
		if not (d is Dictionary) or (d as Dictionary).size() > 16:
			errs.append("emit_event.data debe ser un objeto de hasta 16 claves")
		else:
			for k in d:
				if not (d[k] is float or d[k] is int or d[k] is String or d[k] is bool):
					errs.append("emit_event.data.%s debe ser numero, texto o booleano" % str(k))
	return errs


func resolve(ctx: ActionContext, effect: Dictionary) -> void:
	var first: String = ctx.targets[0].id if not ctx.targets.is_empty() else ""
	ctx.engine.emit("user." + str(effect["name"]), ctx.actor.id, first, (effect.get("data", {}) as Dictionary).duplicate(), ctx.cause_id)
