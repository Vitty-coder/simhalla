class_name ConditionEvaluator
extends RefCounted
## Condiciones declarativas evaluadas por el MOTOR (restricciones de habilidades,
## disparadores de reacciones). No es la vista limitada de la IA: aqui se
## consulta el estado real, pero solo por rutas de una lista permitida.
##
## {"<scope>.<campo>": {"<op>": valor, ...}, ...}  (todas deben cumplirse)
##   scope: self | target | event
##   campos de entidad (self/target): hp, hp_max, hp_ratio, res.<recurso>,
##          status.<id> (pilas; 0 si no esta), tag.<etiqueta> (1/0)
##   campos de evento: type, source, target (relacion respecto a self:
##          "self"|"ally"|"enemy"), y cualquier clave de los datos del evento
##          (amount, applied, crit, element, damage_type, ability, status, resource...)
##   op: lt le gt ge eq ne    valor: numero, texto o booleano
const OPS := ["lt", "le", "gt", "ge", "eq", "ne"]
const ENTITY_FIELDS := ["hp", "hp_max", "hp_ratio"]


static func validate(conds: Variant, label: String, allow_event: bool) -> Array:
	var errs: Array = []
	if not (conds is Dictionary):
		return ["%s debe ser un objeto" % label]
	for key in conds:
		var parts := str(key).split(".")
		var scope := parts[0]
		if not ["self", "target", "event"].has(scope) or parts.size() < 2:
			errs.append("%s: ruta invalida '%s' (use self.*, target.* o event.*)" % [label, str(key)])
			continue
		if scope == "event" and not allow_event:
			errs.append("%s: 'event.*' solo es valido en disparadores" % label)
		if scope != "event":
			var f := parts[1]
			if not (ENTITY_FIELDS.has(f) or (["res", "status", "tag"].has(f) and parts.size() == 3)):
				errs.append("%s: campo desconocido '%s'" % [label, str(key)])
		var cmp: Variant = conds[key]
		if not (cmp is Dictionary) or (cmp as Dictionary).is_empty():
			errs.append("%s.%s debe ser un objeto de comparadores" % [label, str(key)])
			continue
		for op in cmp:
			if not OPS.has(str(op)):
				errs.append("%s.%s: comparador desconocido '%s'" % [label, str(key), str(op)])
			elif not (cmp[op] is float or cmp[op] is int or cmp[op] is String or cmp[op] is bool):
				errs.append("%s.%s.%s: valor debe ser numero, texto o booleano" % [label, str(key), str(op)])
	return errs


static func holds(engine: CombatEngine, conds: Dictionary, self_e: CombatEntity, target_e: CombatEntity, ev: CombatEvent) -> bool:
	for key in conds:
		var v: Variant = _lookup(engine, str(key), self_e, target_e, ev)
		if v == null:
			return false
		var cmp: Dictionary = conds[key]
		for op in cmp:
			if not _compare(v, str(op), cmp[op]):
				return false
	return true


static func _compare(a: Variant, op: String, b: Variant) -> bool:
	if (a is String) or (b is String):
		match op:
			"eq":
				return str(a) == str(b)
			"ne":
				return str(a) != str(b)
		return false
	var x: float = float(a)
	var y: float = float(b)
	match op:
		"lt":
			return x < y
		"le":
			return x <= y
		"gt":
			return x > y
		"ge":
			return x >= y
		"eq":
			return is_equal_approx(x, y)
		"ne":
			return not is_equal_approx(x, y)
	return false


static func _lookup(engine: CombatEngine, key: String, self_e: CombatEntity, target_e: CombatEntity, ev: CombatEvent) -> Variant:
	var parts := key.split(".")
	match parts[0]:
		"self":
			return _entity_field(self_e, parts)
		"target":
			return _entity_field(target_e, parts)
		"event":
			if ev == null:
				return null
			match parts[1]:
				"type":
					return ev.type
				"source", "target":
					var id := ev.source_id if parts[1] == "source" else ev.target_id
					var other := engine.get_entity(id)
					return engine.relation(self_e, other) if other != null and self_e != null else null
			var k := ".".join(parts.slice(1))
			if ev.data.has(k):
				var d: Variant = ev.data[k]
				if d is bool:
					return 1.0 if d else 0.0
				return d
			return null
	return null


static func _entity_field(e: CombatEntity, parts: Array) -> Variant:
	if e == null:
		return null
	match parts[1]:
		"hp":
			return e.hp
		"hp_max":
			return e.hp_max()
		"hp_ratio":
			return e.hp_ratio()
		"res":
			var r := e.get_resource(str(parts[2]))
			return r.value if r != null else null
		"status":
			return float(e.status_stacks(str(parts[2])))
		"tag":
			return 1.0 if e.has_tag(str(parts[2])) else 0.0
	return null
