class_name StatusDef
extends RefCounted
## Definicion declarativa de un estado (datos inmutables).
##
## Los nombres nativos (poison, burn, ...) viven en content/statuses/native_statuses.json
## como DATOS: el motor no impone sus efectos matematicos. Los estados personalizados
## se definen igual (paquetes: effects.json).
##
## Politicas de reaplicacion (`stacking.policy`):
##   stack_intensity  +1 pila (hasta max_stacks) y reinicia la duracion
##   stack_duration   suma duracion
##   independent      instancias separadas (hasta max_stacks instancias)
##   refresh          reinicia la duracion (pilas iguales)
##   replace          sustituye la instancia anterior
##   keep_strongest   conserva la de mayor magnitud*pilas (empate: la antigua)
##   ignore           no hace nada si ya existe

const POLICIES := ["stack_intensity", "stack_duration", "independent", "refresh", "replace", "keep_strongest", "ignore"]
const KEYS := ["id", "name", "tags", "beneficial", "dispellable", "group", "stacking", "duration", "modifiers",
	"flags", "defense", "periodic", "on_apply", "on_expire", "on_death", "form"]
const FLAG_KEYS := ["skip_turn", "suspend_initiative", "interrupt_channel", "taunt", "block_tags", "block_action_types", "immune_status_tags",
	"suspend_statuses", "suspend_cooldowns"]
const DEFENSE_KEYS := ["immune_damage_types", "immune_elements", "absorb", "reduction", "block", "parry", "reflect",
	"prevent_death", "absorb_elements"]
const MODIFIER_KEYS := ["stat", "kind", "value", "per_stack", "priority"]
const KINDS := {"set": StatModifier.Kind.SET, "flat": StatModifier.Kind.FLAT, "pct_add": StatModifier.Kind.PCT_ADD,
	"mult": StatModifier.Kind.MULT, "min": StatModifier.Kind.MIN, "max": StatModifier.Kind.MAX}

var id: String = ""
var display_name: String = ""
var tags: Array[String] = []
var beneficial: bool = false
var dispellable: bool = true
var group: String = ""
var policy: String = "refresh"
var max_stacks: int = 1
var duration_spec: Variant = 3 ## numero (turnos del afectado) o {unit, amount,...}
var modifiers: Array = []
var flags: Dictionary = {}
var defense: Dictionary = {}
var periodic: Array = [] ## [{on, effects}]
var on_apply: Array = []
var on_expire: Array = []
var on_death: Array = [] ## efectos al morir el afectado (p. ej. propagar el estado)
var form: Dictionary = {} ## {add_abilities, remove_abilities, ai}


## Devuelve {"def": StatusDef|null, "errors": Array}.
static func from_dict(d: Dictionary, registry: OperationRegistry) -> Dictionary:
	var errs: Array = []
	var s := StatusDef.new()
	s.id = str(d.get("id", ""))
	var lbl := "estado '%s'" % s.id
	for k in d:
		if not KEYS.has(str(k)):
			errs.append("%s: propiedad desconocida '%s' (permitidas: %s)" % [lbl, str(k), ", ".join(KEYS)])
	if s.id == "":
		errs.append("estado sin 'id'")
	s.display_name = str(d.get("name", s.id))
	for t in d.get("tags", []):
		s.tags.append(str(t))
	s.beneficial = bool(d.get("beneficial", false))
	s.dispellable = bool(d.get("dispellable", true))
	s.group = str(d.get("group", ""))
	var st: Variant = d.get("stacking", {})
	if st is Dictionary:
		for k in st:
			if not ["policy", "max_stacks"].has(str(k)):
				errs.append("%s: stacking.%s desconocido" % [lbl, str(k)])
		s.policy = str(st.get("policy", "refresh"))
		if not POLICIES.has(s.policy):
			errs.append("%s: stacking.policy desconocida '%s' (use %s)" % [lbl, s.policy, ", ".join(POLICIES)])
		s.max_stacks = int(st.get("max_stacks", 99 if s.policy in ["stack_intensity", "independent"] else 1))
		if s.max_stacks < 1 or s.max_stacks > 99:
			errs.append("%s: stacking.max_stacks debe estar entre 1 y 99" % lbl)
	else:
		errs.append("%s: 'stacking' debe ser un objeto" % lbl)
	if d.has("duration"):
		errs.append_array(Duration.validate(d["duration"], lbl + " duration"))
		s.duration_spec = d["duration"]
	var mods: Variant = d.get("modifiers", [])
	if mods is Array:
		for i in (mods as Array).size():
			errs.append_array(validate_modifier(mods[i], "%s modifiers[%d]" % [lbl, i]))
		s.modifiers = (mods as Array).duplicate(true)
	else:
		errs.append("%s: 'modifiers' debe ser una lista" % lbl)
	var fl: Variant = d.get("flags", {})
	if fl is Dictionary:
		for k in fl:
			if not FLAG_KEYS.has(str(k)):
				errs.append("%s: flags.%s desconocido (permitidos: %s)" % [lbl, str(k), ", ".join(FLAG_KEYS)])
		if fl.has("suspend_statuses"):
			if not (fl["suspend_statuses"] is Array) or (fl["suspend_statuses"] as Array).is_empty():
				errs.append("%s: flags.suspend_statuses debe ser una lista no vacia de etiquetas (o [\"*\"])" % lbl)
		if fl.has("suspend_cooldowns") and not (fl["suspend_cooldowns"] is bool):
			errs.append("%s: flags.suspend_cooldowns debe ser booleano" % lbl)
		s.flags = (fl as Dictionary).duplicate(true)
	else:
		errs.append("%s: 'flags' debe ser un objeto" % lbl)
	var df: Variant = d.get("defense", {})
	if df is Dictionary:
		for k in df:
			if not DEFENSE_KEYS.has(str(k)):
				errs.append("%s: defense.%s desconocido (permitidos: %s)" % [lbl, str(k), ", ".join(DEFENSE_KEYS)])
		errs.append_array(_validate_defense(df, lbl))
		s.defense = (df as Dictionary).duplicate(true)
	else:
		errs.append("%s: 'defense' debe ser un objeto" % lbl)
	for key in ["on_apply", "on_expire", "on_death"]:
		var v: Variant = d.get(key, [])
		if v is Array:
			for i in (v as Array).size():
				if not (v[i] is Dictionary):
					errs.append("%s: %s[%d] debe ser un objeto" % [lbl, key, i])
					continue
				for e in registry.validate_effect(v[i]):
					errs.append("%s: %s[%d]: %s" % [lbl, key, i, str(e)])
			match key:
				"on_apply":
					s.on_apply = (v as Array).duplicate(true)
				"on_expire":
					s.on_expire = (v as Array).duplicate(true)
				_:
					s.on_death = (v as Array).duplicate(true)
		else:
			errs.append("%s: '%s' debe ser una lista" % [lbl, key])
	var per: Variant = d.get("periodic", [])
	if per is Array:
		for i in (per as Array).size():
			var p: Variant = per[i]
			if not (p is Dictionary):
				errs.append("%s: periodic[%d] debe ser un objeto" % [lbl, i])
				continue
			for k in p:
				if not ["on", "effects"].has(str(k)):
					errs.append("%s: periodic[%d].%s desconocido" % [lbl, i, str(k)])
			if not ["turn_start", "turn_end"].has(str(p.get("on", ""))):
				errs.append("%s: periodic[%d].on debe ser turn_start o turn_end" % [lbl, i])
			var ef: Variant = p.get("effects", [])
			if not (ef is Array) or (ef as Array).is_empty():
				errs.append("%s: periodic[%d].effects debe ser una lista no vacia" % [lbl, i])
			else:
				for j in (ef as Array).size():
					if not (ef[j] is Dictionary):
						errs.append("%s: periodic[%d].effects[%d] debe ser un objeto" % [lbl, i, j])
						continue
					for e in registry.validate_effect(ef[j]):
						errs.append("%s: periodic[%d].effects[%d]: %s" % [lbl, i, j, str(e)])
		s.periodic = (per as Array).duplicate(true)
	else:
		errs.append("%s: 'periodic' debe ser una lista" % lbl)
	var fm: Variant = d.get("form", {})
	if fm is Dictionary:
		for k in fm:
			if not ["add_abilities", "remove_abilities", "ai"].has(str(k)):
				errs.append("%s: form.%s desconocido" % [lbl, str(k)])
		for ad in fm.get("add_abilities", []):
			if not (ad is Dictionary):
				errs.append("%s: form.add_abilities: cada habilidad debe ser un objeto" % lbl)
				continue
			var ar := AbilityDef.from_dict(ad, registry)
			for ae in ar["errors"]:
				errs.append("%s: form.%s" % [lbl, str(ae)])
		if fm.has("ai"):
			for ae in AIFactory.build(fm["ai"])["errors"]:
				errs.append("%s: form.ai: %s" % [lbl, str(ae)])
		s.form = (fm as Dictionary).duplicate(true)
	else:
		errs.append("%s: 'form' debe ser un objeto" % lbl)
	if not errs.is_empty():
		return {"def": null, "errors": errs}
	return {"def": s, "errors": errs}


static func validate_modifier(m: Variant, label: String) -> Array:
	var errs: Array = []
	if not (m is Dictionary):
		return ["%s debe ser un objeto" % label]
	for k in m:
		if not MODIFIER_KEYS.has(str(k)):
			errs.append("%s: propiedad desconocida '%s'" % [label, str(k)])
	if str(m.get("stat", "")) == "":
		errs.append("%s: falta 'stat'" % label)
	if not KINDS.has(str(m.get("kind", ""))):
		errs.append("%s: kind invalido '%s' (use %s)" % [label, str(m.get("kind", "")), ", ".join(KINDS.keys())])
	if not (m.get("value", null) is float or m.get("value", null) is int):
		errs.append("%s: 'value' debe ser numerico" % label)
	return errs


static func _validate_defense(df: Dictionary, lbl: String) -> Array:
	var errs: Array = []
	for k in ["immune_damage_types", "immune_elements", "absorb_elements"]:
		if df.has(k) and not (df[k] is Array):
			errs.append("%s: defense.%s debe ser una lista" % [lbl, k])
	for t in df.get("immune_damage_types", []):
		if not AbilityDef.DAMAGE_TYPES.has(str(t)):
			errs.append("%s: defense.immune_damage_types: tipo invalido '%s'" % [lbl, str(t)])
	var sub := {"absorb": ["amount", "damage_types", "elements"], "reduction": ["flat", "pct", "damage_types"],
		"block": ["chance", "pct"], "parry": ["chance"], "reflect": ["pct"], "prevent_death": ["survive_hp"]}
	for k in sub:
		if df.has(k):
			if not (df[k] is Dictionary):
				errs.append("%s: defense.%s debe ser un objeto" % [lbl, k])
				continue
			for kk in df[k]:
				if not (sub[k] as Array).has(str(kk)):
					errs.append("%s: defense.%s.%s desconocido (permitidos: %s)" % [lbl, k, str(kk), ", ".join(sub[k])])
	if df.has("absorb") and df["absorb"] is Dictionary:
		errs.append_array(EffectOperation.validate_formula(df["absorb"].get("amount", null), lbl + " defense.absorb.amount"))
	return errs
