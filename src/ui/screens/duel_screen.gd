class_name DuelScreen
extends BaseScreen
## Configuracion de duelo: contendientes (paquete + restriccion de version, IA alternativa), reglamento, perfil, modo libre/reglamentado,
## presupuesto, semilla. Muestra versiones, coste, presupuesto y advertencias ANTES del combate; el boton se desactiva si el modo
## reglamentado no se cumple.

const AI_PRESETS := {
	"": null,
	"passive": {"type": "passive"},
	"scored": {"type": "scored", "weights": {"damage": 1.0, "lethal": 3.0, "heal": 1.0, "need": 2.0, "cost": -0.1}},
	"priority_basic": {"type": "priority_list", "rules": [{"ability": "basic_attack", "target": "lowest_hp_enemy"}]},
}
var source_option: OptionButton
var message: String = ""


static func sources(a: AppController) -> Array:
	var out: Array = []
	for e in a.storage.library.list():
		if str(e["type"]) == "character" and not out.any(func(s): return s["ref"] == e["id"]):
			out.append({"kind": "pkg", "ref": e["id"], "text": "pkg · %s" % e["id"]})
	var d := DirAccess.open("res://content/fixtures/entities")
	if d != null:
		var files := Array(d.get_files())
		files.sort()
		for f in files:
			if str(f).ends_with(".json"):
				out.append({"kind": "file", "ref": "res://content/fixtures/entities/" + str(f), "text": "file · " + str(f).get_basename()})
	return out


func build() -> void:
	var dm := app.duel
	body.add_child(UIKit.header(t("nav.duel"), 1))
	body.add_child(context_line())
	for i in dm.entities.size():
		var e: Dictionary = dm.entities[i]
		var team := UIKit.line_edit(str(e["team"]))
		team.custom_minimum_size.x = 60
		team.text_changed.connect(func(s: String): e["team"] = s)
		team.text_submitted.connect(func(_s: String): refresh())
		var ver := UIKit.line_edit(str(e["constraint"]), "*")
		ver.custom_minimum_size.x = 90
		ver.text_changed.connect(func(s: String): e["constraint"] = s)
		ver.text_submitted.connect(func(_s: String): refresh())
		var ais: Array = AI_PRESETS.keys()
		var ai_opt := UIKit.option(ais.map(func(k): return k if k != "" else t("duel.ai_default")), null)
		for j in ais.size():
			if AI_PRESETS[ais[j]] == e["ai"]:
				ai_opt.select(j)
		ai_opt.item_selected.connect(func(j: int): e["ai"] = AI_PRESETS[ais[j]]; refresh())
		var rm := UIKit.button("✕", func(): dm.remove(i); refresh())
		rm.name = "remove_%d" % i
		var row := UIKit.row([UIKit.label("%d. %s" % [i + 1, e["name"]]), UIKit.label(t("duel.version")), ver, UIKit.label(t("duel.team")), team, ai_opt, rm])
		body.add_child(row)
	var srcs := sources(app)
	source_option = UIKit.option(srcs.map(func(s): return s["text"]))
	source_option.name = "source_option"
	var add := UIKit.button(t("duel.add"), func():
		if srcs.is_empty():
			return
		var s: Dictionary = srcs[source_option.selected]
		if s["kind"] == "pkg":
			dm.add_package(str(s["ref"]))
		else:
			dm.add_file(str(s["ref"]))
		refresh())
	add.name = "add_btn"
	body.add_child(UIKit.row([source_option, add]))
	# reglamento, perfil, modo, presupuesto, semilla
	var rs_ids: Array = app.rules.rulesets().map(func(r): return r["id"])
	var rs_opt := UIKit.option(rs_ids, dm.ruleset_id)
	rs_opt.item_selected.connect(func(j: int): dm.ruleset_id = rs_ids[j]; refresh())
	var pf_ids: Array = app.rules.profiles().map(func(r): return r["id"])
	var pf_opt := UIKit.option(pf_ids, dm.profile_id)
	pf_opt.item_selected.connect(func(j: int): dm.profile_id = pf_ids[j]; refresh())
	var modes := ["free", "regulated"]
	var mode_opt := UIKit.option(modes.map(func(m): return t("mode." + m)), null)
	mode_opt.select(modes.find(dm.mode))
	mode_opt.name = "mode_option"
	mode_opt.item_selected.connect(func(j: int): dm.mode = modes[j]; refresh())
	var prof := app.profile(dm.profile_id)
	var budgets: Array = prof.budgets.keys()
	var bud_opt := UIKit.option(budgets, dm.budget)
	bud_opt.item_selected.connect(func(j: int): dm.budget = budgets[j]; refresh())
	body.add_child(UIKit.row([UIKit.label(t("duel.ruleset")), rs_opt, UIKit.label(t("duel.profile")), pf_opt]))
	body.add_child(UIKit.row([UIKit.label(t("duel.mode")), mode_opt, UIKit.label(t("duel.budget")), bud_opt]))
	var seed_box := SpinBox.new()
	seed_box.min_value = 0
	seed_box.max_value = 2147483647
	seed_box.value = dm.seed_value
	seed_box.custom_minimum_size.y = UIKit.TOUCH_MIN
	seed_box.value_changed.connect(func(v: float): dm.seed_value = int(v))
	body.add_child(UIKit.row([UIKit.label(t("duel.seed")), seed_box]))
	# validacion previa
	var v := dm.validate()
	body.add_child(UIKit.header(t("duel.validation"), 2))
	body.add_child(UIKit.label(t("duel.mode_banner", [v["mode_label"]])))
	for r in v["entities"]:
		if r.has("cost"):
			body.add_child(UIKit.label(t("duel.entity_cost", [r["name"], str(r["resolved"].get("version", "—")), ReportDocument.num(r["cost"]), ReportDocument.num(r["budget_points"]), ReportDocument.num(r["remaining"]), str(r["resolved"].get("hash", "")).substr(0, 10)])))
		else:
			body.add_child(UIKit.error("%s: %s" % [r["name"], "; ".join(r["errors"])]))
	for w in v["warnings"]:
		body.add_child(UIKit.warn(str(w)))
	for e in v["errors"]:
		body.add_child(UIKit.error(str(e)))
	if message != "":
		body.add_child(UIKit.error(message))
	var start := UIKit.button(t("duel.start"), func():
		var r := dm.start()
		if bool(r["ok"]):
			message = ""
			app.go("viewer")
		else:
			message = "; ".join(r["errors"])
			refresh())
	start.name = "start_btn"
	start.disabled = not bool(v["can_start"])
	body.add_child(start)
