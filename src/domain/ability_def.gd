class_name AbilityDef
extends RefCounted
## Definicion declarativa de una habilidad (datos inmutables).
##
## Fase 1: efectos "damage" y "heal", coste en recursos, tipos de accion
## main/free/reaction y objetivos simples. El catalogo completo de operaciones,
## restricciones (cooldown, usos, cargas) y categorias llega en la fase 3 a
## traves del OperationRegistry, sin cambiar este contrato.

enum ActionType { MAIN, FREE, REACTION }

const TARGETINGS := ["enemy", "ally", "self", "any"]
const DAMAGE_TYPES := ["physical", "magical", "true"]
const ALLOWED_KEYS := ["id", "name", "action_type", "targeting", "target_count", "cost", "tags", "effects",
	"cooldown", "uses_per_combat", "uses_per_turn", "charges", "requires", "trigger", "passive", "cast_time",
	"interruptible", "ignore_taunt"]
const TRIGGER_KEYS := ["event", "when", "target", "chance", "while_dead", "limit_per_turn"]
const TRIGGER_TARGETS := ["self", "event_source", "event_target", "lowest_hp_enemy", "first_enemy", "random_enemy"]

var id: String = ""
var display_name: String = ""
var action_type: ActionType = ActionType.MAIN
var targeting: String = "enemy" ## enemy | ally (sin el propio) | self | any
var target_count: int = 1
var cost: Dictionary = {} ## recurso -> cantidad
var tags: Array[String] = []
var effects: Array = [] ## Array[Dictionary] de operaciones
var is_basic_attack: bool = false

# --- Fase 3: restricciones, disparadores, pasivas, canalizacion ---
var cooldown: Variant = null ## numero (turnos del dueno) o {unit, amount,...}
var uses_per_combat: int = 0 ## 0 = ilimitado
var uses_per_turn: int = 0
var charges: Dictionary = {} ## {max, initial, recharge: duracion}
var requires: Dictionary = {} ## condiciones (ConditionEvaluator)
var trigger: Dictionary = {} ## {event, when, target, chance, while_dead, limit_per_turn}
var passive_modifiers: Array = []
var cast_time: float = 0.0 ## > 0: canalizada/cargada (tiempo virtual)
var interruptible: bool = true
var ignore_taunt: bool = false


func is_triggered() -> bool:
	return not trigger.is_empty()


## Devuelve {"ability": AbilityDef|null, "errors": Array[String]}.
static func from_dict(d: Dictionary, registry: OperationRegistry) -> Dictionary:
	var errs: Array[String] = []
	var a := AbilityDef.new()
	a.id = str(d.get("id", ""))
	for k in d:
		if not ALLOWED_KEYS.has(str(k)):
			errs.append("habilidad '%s': propiedad desconocida '%s' (permitidas: %s)" % [a.id, str(k), ", ".join(ALLOWED_KEYS)])
	if a.id == "":
		errs.append("habilidad sin 'id'")
	a.display_name = str(d.get("name", a.id))
	var at := str(d.get("action_type", "main"))
	match at:
		"main":
			a.action_type = ActionType.MAIN
		"free":
			a.action_type = ActionType.FREE
		"reaction":
			a.action_type = ActionType.REACTION
		_:
			errs.append("habilidad '%s': action_type desconocido '%s'" % [a.id, at])
	a.targeting = str(d.get("targeting", "enemy"))
	if not TARGETINGS.has(a.targeting):
		errs.append("habilidad '%s': targeting desconocido '%s'" % [a.id, a.targeting])
	a.target_count = int(d.get("target_count", 1))
	if a.target_count < 1:
		errs.append("habilidad '%s': target_count debe ser >= 1" % a.id)
	var cost_v: Variant = d.get("cost", {})
	if cost_v is Dictionary:
		for k in cost_v:
			if float(cost_v[k]) < 0.0:
				errs.append("habilidad '%s': coste negativo en '%s'" % [a.id, str(k)])
			a.cost[str(k)] = float(cost_v[k])
	else:
		errs.append("habilidad '%s': 'cost' debe ser un objeto" % a.id)
	for t in d.get("tags", []):
		a.tags.append(str(t))
	var eff: Variant = d.get("effects", [])
	if not (eff is Array):
		errs.append("habilidad '%s': 'effects' debe ser una lista" % a.id)
	else:
		for i in (eff as Array).size():
			var e: Variant = eff[i]
			if not (e is Dictionary):
				errs.append("habilidad '%s': effects[%d] debe ser un objeto" % [a.id, i])
				continue
			var op_errs := registry.validate_effect(e)
			for oe in op_errs:
				errs.append("habilidad '%s': effects[%d]: %s" % [a.id, i, oe])
			a.effects.append((e as Dictionary).duplicate(true))
	_parse_phase3(d, a, errs)
	if errs.is_empty():
		return {"ability": a, "errors": errs}
	return {"ability": null, "errors": errs}


func action_type_name() -> String:
	return ActionType.keys()[action_type].to_lower()


static func _parse_phase3(d: Dictionary, a: AbilityDef, errs: Array[String]) -> void:
	var lbl := "habilidad '%s'" % a.id
	if d.has("cooldown"):
		var ev := Duration.validate(d["cooldown"], lbl + " cooldown")
		if d["cooldown"] is Dictionary and str(d["cooldown"].get("unit", "target_turns")) in ["permanent", "caster_turns"]:
			ev.append("%s cooldown: unit no admitida para cooldowns" % lbl)
		for e in ev:
			errs.append(str(e))
		a.cooldown = d["cooldown"]
	for k in ["uses_per_combat", "uses_per_turn"]:
		if d.has(k):
			if not (d[k] is float or d[k] is int) or int(d[k]) < 1:
				errs.append("%s: %s debe ser un entero >= 1" % [lbl, k])
			elif k == "uses_per_combat":
				a.uses_per_combat = int(d[k])
			else:
				a.uses_per_turn = int(d[k])
	if d.has("charges"):
		var c: Variant = d["charges"]
		if not (c is Dictionary):
			errs.append("%s: charges debe ser un objeto" % lbl)
		else:
			for k in c:
				if not ["max", "initial", "recharge"].has(str(k)):
					errs.append("%s: charges.%s desconocido" % [lbl, str(k)])
			if not (c.get("max", null) is float or c.get("max", null) is int) or int(c.get("max", 0)) < 1:
				errs.append("%s: charges.max debe ser un entero >= 1" % lbl)
			if c.has("initial") and (not (c["initial"] is float or c["initial"] is int) or int(c["initial"]) < 0 or int(c["initial"]) > int(c.get("max", 0))):
				errs.append("%s: charges.initial debe estar entre 0 y max" % lbl)
			if c.has("recharge"):
				for e in Duration.validate(c["recharge"], lbl + " charges.recharge"):
					errs.append(str(e))
			a.charges = (c as Dictionary).duplicate(true)
	if d.has("requires"):
		for e in ConditionEvaluator.validate(d["requires"], lbl + " requires", false):
			errs.append(str(e))
		if d["requires"] is Dictionary:
			a.requires = (d["requires"] as Dictionary).duplicate(true)
	if d.has("trigger"):
		var t: Variant = d["trigger"]
		if not (t is Dictionary):
			errs.append("%s: trigger debe ser un objeto" % lbl)
		else:
			for k in t:
				if not TRIGGER_KEYS.has(str(k)):
					errs.append("%s: trigger.%s desconocido (permitidos: %s)" % [lbl, str(k), ", ".join(TRIGGER_KEYS)])
			if str(t.get("event", "")) == "":
				errs.append("%s: trigger.event es obligatorio" % lbl)
			if t.has("target") and not TRIGGER_TARGETS.has(str(t["target"])):
				errs.append("%s: trigger.target invalido (use %s)" % [lbl, ", ".join(TRIGGER_TARGETS)])
			if t.has("chance") and (not (t["chance"] is float or t["chance"] is int) or float(t["chance"]) < 0.0 or float(t["chance"]) > 1.0):
				errs.append("%s: trigger.chance debe estar entre 0 y 1" % lbl)
			if t.has("limit_per_turn") and (not (t["limit_per_turn"] is float or t["limit_per_turn"] is int) or int(t["limit_per_turn"]) < 1):
				errs.append("%s: trigger.limit_per_turn debe ser un entero >= 1" % lbl)
			if t.has("when"):
				for e in ConditionEvaluator.validate(t["when"], lbl + " trigger.when", true):
					errs.append(str(e))
			a.trigger = (t as Dictionary).duplicate(true)
	if d.has("passive"):
		var p: Variant = d["passive"]
		if not (p is Dictionary):
			errs.append("%s: passive debe ser un objeto" % lbl)
		else:
			for k in p:
				if str(k) != "modifiers":
					errs.append("%s: passive.%s desconocido" % [lbl, str(k)])
			var mods: Variant = p.get("modifiers", [])
			if mods is Array:
				for i in (mods as Array).size():
					for e in StatusDef.validate_modifier(mods[i], "%s passive.modifiers[%d]" % [lbl, i]):
						errs.append(str(e))
				a.passive_modifiers = (mods as Array).duplicate(true)
			else:
				errs.append("%s: passive.modifiers debe ser una lista" % lbl)
	if d.has("cast_time"):
		if not (d["cast_time"] is float or d["cast_time"] is int) or float(d["cast_time"]) <= 0.0:
			errs.append("%s: cast_time debe ser un numero > 0" % lbl)
		else:
			a.cast_time = float(d["cast_time"])
	if d.has("interruptible"):
		if d["interruptible"] is bool:
			a.interruptible = d["interruptible"]
		else:
			errs.append("%s: interruptible debe ser booleano" % lbl)
	if d.has("ignore_taunt"):
		if d["ignore_taunt"] is bool:
			a.ignore_taunt = d["ignore_taunt"]
		else:
			errs.append("%s: ignore_taunt debe ser booleano" % lbl)
	if not a.trigger.is_empty() and a.cast_time > 0.0:
		errs.append("%s: una habilidad con trigger no puede canalizarse (cast_time)" % lbl)
