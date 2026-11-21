class_name EventText
extends RefCounted
## Texto legible (localizado) de un evento del registro para el visor de batalla. Solo presentacion: la verdad es el evento.

## Eventos mostrados en el registro del visor (el resto es ruido tecnico: time_advanced, damage_pre, hp_changed...).
const VISIBLE := ["turn_started", "action_selected", "damage_dealt", "heal_done", "miss", "crit", "status_gained", "status_removed", "status_expired",
	"death", "wait", "reaction_triggered", "reaction_declined", "ai_fallback", "action_rejected", "summon_created", "transformed", "channel_started",
	"channel_completed", "limit_reached", "combat_ended", "error", "script_run"]


static func is_visible(type: String) -> bool:
	return VISIBLE.has(type) or type.begins_with("user.")


static func describe(ev: Dictionary) -> String:
	var t := str(ev["type"])
	var d: Dictionary = ev.get("data", {})
	var key := "ev." + t
	var src := str(ev.get("source", ""))
	var tgt := str(ev.get("target", ""))
	match t:
		"turn_started":
			return LocaleService.t(key, [src, d.get("turn", "")])
		"action_selected":
			if str(d.get("kind", "")) == "wait":
				return LocaleService.t("ev.wait_decision", [src])
			return LocaleService.t(key, [src, d.get("ability", "?"), tgt, d.get("reason", "")])
		"damage_dealt":
			return LocaleService.t(key, [src, ReportDocument.num(d.get("applied", 0.0)), tgt, str(d.get("damage_type", "")) + ("/" + str(d["element"]) if str(d.get("element", "")) != "" else ""), " ★" if bool(d.get("crit", false)) else ""])
		"heal_done":
			return LocaleService.t(key, [src, ReportDocument.num(d.get("applied", 0.0)), tgt])
		"miss", "crit", "wait", "death", "reaction_declined", "channel_started", "channel_completed":
			return LocaleService.t(key, [src, tgt])
		"status_gained", "status_removed", "status_expired":
			return LocaleService.t(key, [tgt, d.get("status", "?")])
		"reaction_triggered":
			return LocaleService.t(key, [src, d.get("ability", "?"), tgt])
		"combat_ended":
			return LocaleService.t(key, [d.get("outcome", ""), d.get("winner_team", ""), d.get("reason", "")])
		"error":
			return LocaleService.t(key, [d.get("code", ""), d.get("message", "")])
	if t.begins_with("user."):
		return LocaleService.t("ev.user", [t.substr(5), src])
	var generic := LocaleService.t(key, [src, tgt, str(d)])
	return generic if generic != key else "%s %s→%s" % [t, src, tgt]
