class_name AIPredictor
extends RefCounted
## Consultas de prediccion de la IA. Funciones puras sobre la VISTA (y su memoria):
## nunca tocan el estado real, no consumen RNG y no conocen estadisticas ocultas
## del rival. Lo que no se puede saber se devuelve como estimacion con rango
## (`known=false`) o `null` (desconocido).
##
## Mitigacion/resistencia del rival: solo la OBSERVADA en el propio dano causado
## (razon importe/pre-mitigacion por tipo y elemento, memoria `obs.<id>.mit`).
## Sin observaciones: se supone sin mitigacion (maximo) y el minimo es 0.
## Probabilidad de impactar: tasa observada si hay >= MIN_SWINGS tiradas; si no,
## la ACC propia acotada (EVA del rival desconocida).

const MIN_SWINGS := 2
const DEFAULT_HIT := 0.95


static func _ability(view: Dictionary, ability_id: String) -> Dictionary:
	for a in view["self"]["abilities"]:
		if a["id"] == ability_id:
			return a
	return {}


static func _other(view: Dictionary, id: String) -> Dictionary:
	for o in view["others"]:
		if o["id"] == id:
			return o
	return {}


static func _obs(view: Dictionary, id: String) -> Dictionary:
	return view["self"]["memory"].get("obs", {}).get(id, {})


## Razon de mitigacion observada para (tipo, elemento): {"ratio": float, "known": bool}.
static func observed_ratio(view: Dictionary, target_id: String, damage_type: String, element: String) -> Dictionary:
	if damage_type == "true":
		return {"ratio": 1.0, "known": true}
	var mit: Dictionary = _obs(view, target_id).get("mit", {})
	var key := "%s|%s" % [damage_type, element]
	if mit.has(key) and float(mit[key]["pre"]) > 0.0:
		return {"ratio": float(mit[key]["amt"]) / float(mit[key]["pre"]), "known": true}
	# sin dato exacto: media de lo observado para ese tipo de dano (cualquier elemento)
	var pre := 0.0
	var amt := 0.0
	for k in mit:
		if str(k).begins_with(damage_type + "|"):
			pre += float(mit[k]["pre"])
			amt += float(mit[k]["amt"])
	if pre > 0.0:
		return {"ratio": amt / pre, "known": false}
	return {"ratio": 1.0, "known": false}


## Probabilidad estimada de impactar a `target_id` con la habilidad.
static func hit_chance(view: Dictionary, ability_id: String, target_id: String) -> float:
	var prof: Dictionary = _ability(view, ability_id).get("profile", {})
	var dmg: Array = prof.get("damage", [])
	if dmg.is_empty() or dmg.all(func(c): return bool(c["always_hit"])):
		return 1.0
	var o := _obs(view, target_id)
	if int(o.get("swings", 0)) >= MIN_SWINGS:
		return clampf(float(o["hits"]) / float(o["swings"]), 0.0, 1.0)
	var acc: float = float(view["self"]["stats"].get("ACC", DEFAULT_HIT))
	return clampf(acc, 0.05, 1.0)


## Dano estimado sobre un objetivo: {min, expected, max, expected_total, known, hit_chance, lethal, lethal_potential}
## `expected`: por impacto sin critico. `max`: critico y sin mitigacion. `expected_total`: ponderado por
## probabilidad de impacto y critico. lethal = (known y expected >= hp visible); lethal_potential = max >= hp.
static func damage(view: Dictionary, ability_id: String, target_id: String) -> Dictionary:
	var prof: Dictionary = _ability(view, ability_id).get("profile", {})
	var stats: Dictionary = view["self"]["stats"]
	var hit := hit_chance(view, ability_id, target_id)
	var lo := 0.0
	var ex := 0.0
	var hi := 0.0
	var total := 0.0
	var all_known := true
	var any_dmg := false
	var crit_chance := clampf(float(stats.get("CRIT", 0.0)), 0.0, 1.0)
	var crit_mult := maxf(float(stats.get("CRIT_DMG", 1.0)), 1.0)
	for c in prof.get("damage", []):
		any_dmg = true
		if c["base"] == null:
			all_known = false # formula con target.*: no resoluble sin ver al rival
			continue
		var base := maxf(float(c["base"]), 0.0)
		var element: String = c["element"]
		if element != "":
			base *= maxf(1.0 + float(stats.get("ELEM_AFF." + element, 0.0)), 0.0)
		var obs := observed_ratio(view, target_id, str(c["damage_type"]), element)
		var cm := crit_mult if bool(c["can_crit"]) else 1.0
		ex += base * float(obs["ratio"])
		hi += base * cm
		if bool(obs["known"]):
			lo += base * float(obs["ratio"])
		else:
			all_known = false
		var cc := clampf(crit_chance + float(c["crit_bonus"]), 0.0, 1.0) if bool(c["can_crit"]) else 0.0
		total += base * float(obs["ratio"]) * (1.0 + cc * (crit_mult - 1.0))
	var hp: Variant = _other(view, target_id).get("hp", null)
	var known := any_dmg and all_known
	return {
		"min": lo, "expected": ex, "max": hi, "expected_total": total * hit, "known": known, "hit_chance": hit,
		"lethal": known and hp != null and ex >= float(hp),
		"lethal_potential": any_dmg and hp != null and hi >= float(hp),
	}


## Curacion efectiva estimada sobre un objetivo (limitada por su vida faltante si es visible).
## HEAL_REC del objetivo: la propia si es uno mismo; 1.0 supuesto para los demas.
static func heal(view: Dictionary, ability_id: String, target_id: String) -> Dictionary:
	var prof: Dictionary = _ability(view, ability_id).get("profile", {})
	var raw := 0.0
	var known := true
	for h in prof.get("heals", []):
		if h["base"] == null:
			known = false
			continue
		raw += float(h["base"])
	var rec := 1.0
	var tgt: Dictionary = view["self"] if target_id == view["self"]["id"] else _other(view, target_id)
	if target_id == view["self"]["id"]:
		rec = float(view["self"]["stats"].get("HEAL_REC", 1.0))
	else:
		known = false
	var amount := raw * rec
	var missing: Variant = null
	if tgt.has("hp") and tgt.has("hp_max"):
		missing = maxf(float(tgt["hp_max"]) - float(tgt["hp"]), 0.0)
	return {"amount": amount, "effective": minf(amount, float(missing)) if missing != null else amount, "missing": missing, "known": known and not prof.get("heals", []).is_empty()}


## Estados que la habilidad aplicaria sobre el objetivo y cuales no tiene ya (si es visible).
static func statuses(view: Dictionary, ability_id: String, target_id: String) -> Dictionary:
	var prof: Dictionary = _ability(view, ability_id).get("profile", {})
	var ids: Array = prof.get("statuses", [])
	var tgt: Dictionary = view["self"] if target_id == view["self"]["id"] else _other(view, target_id)
	var fresh: Array = []
	for sid in ids:
		var has := false
		if tgt.has("statuses"):
			for st in tgt["statuses"]:
				if str(st["id"]) == str(sid):
					has = true
		if not has:
			fresh.append(sid)
	return {"applies": ids, "new_for_target": fresh, "target_statuses_visible": tgt.has("statuses")}


## Tiempo virtual estimado hasta el proximo turno de `id`: usa SOLO la iniciativa visible y el
## intervalo entre turnos observado; null si aun no se ha podido observar.
static func time_to_turn(view: Dictionary, id: String) -> Variant:
	if id == view["self"]["id"]:
		return null # la SPD propia si se conoce, pero la comparativa es con rivales
	var o := _other(view, id)
	var obs := _obs(view, id)
	if o.is_empty() or not o.has("initiative") or float(obs.get("interval", 0.0)) <= 0.0:
		return null
	var th: float = float(view["atb_threshold"])
	var frac := clampf((th - float(o["initiative"])) / th, 0.0, 1.0)
	return float(obs["interval"]) * frac


## Reacciones previsibles del rival: las observadas en combates previos de ESTA batalla.
static func seen_reactions(view: Dictionary, id: String) -> Array:
	return _obs(view, id).get("reactions_seen", {}).keys()


## Coste relativo de la habilidad respecto a los recursos actuales propios (0..1, media).
static func cost_fraction(view: Dictionary, ability_id: String) -> float:
	var cost: Dictionary = _ability(view, ability_id).get("cost", {})
	if cost.is_empty():
		return 0.0
	var acc := 0.0
	for rid in cost:
		var have := float(view["self"]["resources"].get(rid, 0.0))
		acc += clampf(float(cost[rid]) / maxf(have, 1.0), 0.0, 1.0)
	return acc / float(cost.size())


## Paquete completo para una pareja (habilidad, objetivo): lo que consumen condiciones y puntuaciones.
static func evaluate(view: Dictionary, ability_id: String, target_id: String) -> Dictionary:
	var d := damage(view, ability_id, target_id)
	var h := heal(view, ability_id, target_id)
	var s := statuses(view, ability_id, target_id)
	return {
		"damage": d["expected"], "damage_max": d["max"], "damage_total": d["expected_total"], "damage_known": d["known"],
		"hit_chance": d["hit_chance"], "lethal": d["lethal"], "lethal_potential": d["lethal_potential"],
		"heal": h["effective"], "heal_known": h["known"], "statuses": s,
		"cost_fraction": cost_fraction(view, ability_id),
		"time_to_turn": time_to_turn(view, target_id),
		"reactions_seen": seen_reactions(view, target_id).size(),
	}
