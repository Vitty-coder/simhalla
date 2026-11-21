class_name DefenseService
extends RefCounted
## Defensas nativas aportadas por estados (PROJECT.md 5.4): inmunidad, absorcion
## elemental (a curacion), parada, bloqueo, reduccion plana/porcentual, escudos de
## absorcion, reflejo y prevencion de muerte.
##
## Se implementan como INTERCEPTORES de `damage_pre`/`death_pre` y un observador de
## `damage_dealt` (reflejo); cada cambio queda trazado como event_modified /
## event_cancelled con el estado como origen. Orden (provisional, D-042), por
## estado en orden de aplicacion y dentro de cada uno:
##   inmunidad -> absorcion elemental -> parada -> bloqueo -> reduccion -> escudo
## Nada de esto es gratuito: solo existe si un estado/habilidad lo concede.

const PRIO := -400

var engine: CombatEngine


func _init(eng: CombatEngine) -> void:
	engine = eng


func attach() -> void:
	engine.dispatcher.intercept(EventTypes.DAMAGE_PRE, Callable(self, "_on_damage_pre"), PRIO, "defense_service")
	engine.dispatcher.intercept(EventTypes.DEATH_PRE, Callable(self, "_on_death_pre"), PRIO, "defense_service")
	engine.dispatcher.observe(EventTypes.DAMAGE_DEALT, Callable(self, "_on_damage_dealt"), 10, "defense_service")


static func _filter_ok(df: Dictionary, damage_type: String, element: String) -> bool:
	if df.has("damage_types") and not (df["damage_types"] as Array).has(damage_type):
		return false
	if df.has("elements") and not (df["elements"] as Array).has(element):
		return false
	return true


func _on_damage_pre(ev: CombatEvent, _eng: CombatEngine) -> void:
	var target := engine.get_entity(ev.target_id)
	if target == null:
		return
	var dtype := str(ev.data.get("damage_type", ""))
	var element := str(ev.data.get("element", ""))
	for st: StatusInstance in target.statuses.duplicate():
		var df: Dictionary = st.def.defense
		if df.is_empty() or st.frozen or not target.statuses.has(st):
			continue
		var by := "status:" + st.def.id
		var amount: float = float(ev.data["amount"])
		if amount <= 0.0:
			return
		if (df.get("immune_damage_types", []) as Array).has(dtype) or (element != "" and (df.get("immune_elements", []) as Array).has(element)):
			ev.set_data("amount", 0.0, by)
			continue
		if element != "" and (df.get("absorb_elements", []) as Array).has(element):
			ev.cancel(by, "absorcion elemental")
			engine.direct_heal(target, target, amount, "elemental_absorb", ev.id)
			return
		if df.has("parry"):
			var chance: float = float(df["parry"].get("chance", 0.0))
			var roll: float = engine.rng.stream("proc").next_float()
			engine.emit(EventTypes.PROC, target.id, ev.source_id, {"effect": "parry", "chance": chance, "roll": roll, "success": roll < chance}, ev.id)
			if roll < chance:
				ev.cancel(by, "parada")
				return
		if df.has("block"):
			var bchance: float = float(df["block"].get("chance", 1.0))
			var broll: float = engine.rng.stream("proc").next_float()
			engine.emit(EventTypes.PROC, target.id, ev.source_id, {"effect": "block", "chance": bchance, "roll": broll, "success": broll < bchance}, ev.id)
			if broll < bchance:
				amount = amount * (1.0 - clampf(float(df["block"].get("pct", 0.5)), 0.0, 1.0))
		if df.has("reduction") and _filter_ok(df["reduction"], dtype, element):
			var red: Dictionary = df["reduction"]
			amount = maxf(amount * (1.0 - clampf(float(red.get("pct", 0.0)), 0.0, 1.0)) - float(red.get("flat", 0.0)), 0.0)
		if df.has("absorb") and st.shield > 0.0 and _filter_ok(df["absorb"], dtype, element):
			var take := minf(st.shield, amount)
			st.shield -= take
			amount -= take
			if st.shield <= 0.0:
				if amount != float(ev.data["amount"]):
					ev.set_data("amount", engine.rules.round_value(amount), by)
				engine.status_service.remove(st, "depleted", ev.id)
				continue
		if amount != float(ev.data["amount"]):
			ev.set_data("amount", engine.rules.round_value(amount), by)


func _on_damage_dealt(ev: CombatEvent, _eng: CombatEngine) -> void:
	if bool(ev.data.get("reflected", false)) or float(ev.data.get("applied", 0.0)) <= 0.0:
		return
	var target := engine.get_entity(ev.target_id)
	var attacker := engine.get_entity(ev.source_id)
	if target == null or attacker == null or attacker == target or not attacker.alive:
		return
	for st: StatusInstance in target.statuses.duplicate():
		if st.frozen:
			continue
		var rf: Variant = st.def.defense.get("reflect", null)
		if rf is Dictionary:
			var dmg: float = engine.rules.round_value(float(ev.data["applied"]) * clampf(float(rf.get("pct", 0.0)), 0.0, 1.0))
			if dmg > 0.0:
				engine.deliver_damage(target, attacker, {
					"component": 0, "damage_type": "true", "element": "", "crit": false, "base": dmg, "premitigation": dmg,
					"defense_used": 0.0, "resistance_used": 0.0, "amount": dmg, "reflected": true,
				}, ev.id)
			if not attacker.alive:
				return


func _on_death_pre(ev: CombatEvent, _eng: CombatEngine) -> void:
	var e := engine.get_entity(ev.target_id)
	if e == null:
		return
	for st: StatusInstance in e.statuses.duplicate():
		if st.frozen:
			continue
		var pd: Variant = st.def.defense.get("prevent_death", null)
		if pd is Dictionary:
			var survive: float = minf(float(pd.get("survive_hp", engine.rules.get_path_value("damage.survive_hp"))), e.hp_max())
			engine.change_hp(e, survive - e.hp, "death_prevented", ev.id)
			ev.cancel("status:" + st.def.id, "prevencion de muerte")
			engine.status_service.remove(st, "consumed", ev.id)
			return
