class_name OperationRegistry
extends RefCounted
## Registro de operaciones declarativas disponibles.
##
## Punto de extension: la fase 3 registra aqui estados, recursos, iniciativa,
## invocaciones, restauracion temporal, etc. El motor solo conoce este registro.

## Claves comunes a todas las operaciones: `on` (targets|caster) y `chance` (por objetivo).
const COMMON_KEYS := ["on", "chance"]
const ON_SELECTORS := ["targets", "caster", "all_enemies", "all_allies", "random_enemy", "random_ally", "lowest_hp_enemy"]

var _ops: Dictionary = {}


func _init() -> void:
	register(DamageOperation.new())
	register(HealOperation.new())
	register(ApplyStatusOperation.new())
	register(RemoveStatusOperation.new())
	register(ExtendStatusOperation.new())
	register(TransferStatusOperation.new())
	register(ModifyResourceOperation.new())
	register(ModifyInitiativeOperation.new())
	register(SummonOperation.new())
	register(RecordStateOperation.new())
	register(RestoreStateOperation.new())
	register(DelayedEffectOperation.new())
	register(RepeatActionOperation.new())
	register(CopyActionOperation.new())
	register(EmitEventOperation.new())
	register(MetricOperation.new())
	register(ModifyCooldownOperation.new())
	register(InvertStatusOperation.new())
	register(PropagateStatusOperation.new())
	register(ScriptOperation.new())


func register(op: EffectOperation) -> void:
	op.registry = self
	_ops[op.type_id()] = op


func has_operation(type: String) -> bool:
	return _ops.has(type)


func get_operation(type: String) -> EffectOperation:
	return _ops.get(type, null)


func operation_ids() -> Array:
	var ids: Array = _ops.keys()
	ids.sort()
	return ids


func validate_effect(effect: Dictionary) -> Array:
	var type := str(effect.get("type", ""))
	if type == "":
		return ["efecto sin 'type'"]
	var op: EffectOperation = get_operation(type)
	if op == null:
		return ["operacion desconocida '%s' (disponibles: %s)" % [type, ", ".join(operation_ids())]]
	var allowed: Array = op.allowed_keys() + COMMON_KEYS
	var errs: Array = EffectOperation.check_keys(effect, allowed, type)
	if effect.has("on") and not ON_SELECTORS.has(str(effect["on"])):
		errs.append("%s.on debe ser uno de: %s" % [type, ", ".join(ON_SELECTORS)])
	if effect.has("chance") and (not (effect["chance"] is float or effect["chance"] is int) or float(effect["chance"]) < 0.0 or float(effect["chance"]) > 1.0):
		errs.append("%s.chance debe estar entre 0 y 1" % type)
	errs.append_array(op.validate(effect))
	return errs
