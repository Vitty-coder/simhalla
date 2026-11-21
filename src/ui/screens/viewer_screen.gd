class_name ViewerScreen
extends BaseScreen
## Visor de batalla: retratos, vida, iniciativa, recursos, estados, previsiones de turno, registro cronologico, inspeccion de eventos y
## controles (pausa, avanzar por accion/turno, velocidad, deslizador de posicion, retroceder, al final, repetir). Solo presenta lo que
## devuelve el ViewerModel; no ejecuta reglas.

const SPEEDS := [1, 2, 4, 8, 16, 32]
var vm: ViewerModel
var cards: VBoxContainer
var forecast_label: Label
var status_label: Label
var log_box: VBoxContainer
var inspect_box: VBoxContainer
var slider: HSlider
var play_btn: Button
var result_label: Label
var save_msg: Label
var _accum: float = 0.0
var _updating: bool = false


func build() -> void:
	vm = app.viewer
	body.add_child(UIKit.header(t("nav.viewer"), 1))
	if vm == null:
		body.add_child(UIKit.note(t("viewer.none")))
		body.add_child(UIKit.button(t("viewer.go_duel"), func(): app.go("duel")))
		return
	if not vm.warnings.is_empty():
		for w in vm.warnings:
			body.add_child(UIKit.warn(str(w)))
	status_label = UIKit.label("")
	body.add_child(status_label)
	cards = UIKit.column()
	body.add_child(cards)
	forecast_label = UIKit.note("")
	body.add_child(forecast_label)
	# controles
	play_btn = UIKit.button(t("viewer.play"), func(): vm.toggle(); update_view())
	play_btn.name = "play_btn"
	var step_a := UIKit.button(t("viewer.step_action"), func(): vm.step_action(); update_view())
	step_a.name = "step_action_btn"
	var step_t := UIKit.button(t("viewer.step_turn"), func(): vm.step_turn(); update_view())
	step_t.name = "step_turn_btn"
	var back := UIKit.button("◀", func(): vm.rewind(1); update_view())
	back.name = "rewind_btn"
	var fwd := UIKit.button("▶", func(): vm.forward(1); update_view())
	fwd.name = "forward_btn"
	var end := UIKit.button(t("viewer.to_end"), func(): vm.to_end(); update_view())
	end.name = "to_end_btn"
	var restart := UIKit.button(t("viewer.restart"), func(): vm.restart(); update_view())
	restart.name = "restart_btn"
	var repeat := UIKit.button(t("viewer.repeat"), func(): vm.repeat_same_seed(); update_view())
	var spd := UIKit.option(SPEEDS.map(func(s): return "x%d" % s), null)
	spd.name = "speed_option"
	spd.item_selected.connect(func(i: int): vm.set_speed(SPEEDS[i]))
	body.add_child(UIKit.row([play_btn, step_a, step_t, back, fwd, spd]))
	body.add_child(UIKit.row([end, restart, repeat]))
	slider = HSlider.new()
	slider.name = "seek_slider"
	slider.custom_minimum_size.y = UIKit.TOUCH_MIN
	slider.min_value = 0
	slider.max_value = maxi(vm.total_steps(), 1)
	slider.step = 1
	slider.value_changed.connect(func(v: float):
		if not _updating:
			vm.seek(int(v))
			update_view())
	body.add_child(slider)
	result_label = UIKit.label("")
	body.add_child(result_label)
	body.add_child(UIKit.header(t("viewer.log"), 3))
	log_box = UIKit.column()
	body.add_child(log_box)
	inspect_box = UIKit.column()
	body.add_child(inspect_box)
	# guardar e informar
	var title := UIKit.line_edit("", t("viewer.save_title"))
	title.name = "save_title"
	save_msg = UIKit.label("")
	save_msg.name = "save_msg"
	var save := UIKit.button(t("viewer.save"), func():
		var r := vm.save(title.text, false)
		if bool(r["ok"]):
			var rp := vm.save_report(str(r["id"]), "")
			save_msg.text = t("viewer.saved", [str(r["id"]), str(rp.get("id", ""))])
		else:
			save_msg.text = str(r["error"]))
	save.name = "save_btn"
	body.add_child(UIKit.row([title, save]))
	body.add_child(save_msg)
	update_view()


## Actualiza solo lo dinamico (sin reconstruir los controles: el deslizador y el foco se conservan).
func update_view() -> void:
	if vm == null or cards == null:
		return
	var v := vm.view(40)
	var pos: Dictionary = v["position"]
	status_label.text = t("viewer.status", [pos["step"], pos["total"], ReportDocument.num(v["snapshot"]["time"]), v["snapshot"]["turn"], v["snapshot"]["current_entity"]])
	play_btn.text = t("viewer.pause") if vm.playing else t("viewer.play")
	_updating = true
	slider.max_value = maxi(int(pos["total"]), 1)
	slider.value = pos["step"]
	_updating = false
	UIKit.clear(cards)
	for e in v["snapshot"]["entities"]:
		cards.add_child(_card(e))
	forecast_label.text = t("viewer.forecast", [", ".join(v["forecast"].map(func(f): return "%s@%s" % [f["id"], ReportDocument.num(f["time"], 1)]))])
	UIKit.clear(log_box)
	for line in v["log"]:
		var b := Button.new()
		b.text = "%s  %s" % [ReportDocument.num(line["t"], 1), line["text"]]
		b.alignment = HORIZONTAL_ALIGNMENT_LEFT
		b.flat = true
		b.custom_minimum_size.y = UIKit.TOUCH_MIN
		b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		b.pressed.connect(func(): vm.select_event(int(line["id"])); _show_inspector())
		log_box.add_child(b)
	_show_inspector()
	if not (v["result"] as Dictionary).is_empty():
		var r: Dictionary = v["result"]
		result_label.text = t("viewer.result", [r["outcome"], r["winner_team"], r["reason"]])
	else:
		result_label.text = ""


func _card(e: Dictionary) -> Control:
	var hp := ProgressBar.new()
	hp.min_value = 0
	hp.max_value = maxf(float(e["hp_max"]), 1.0)
	hp.value = float(e["hp"])
	hp.custom_minimum_size = Vector2(160, 18)
	hp.show_percentage = false
	var ini := ProgressBar.new()
	ini.min_value = 0
	ini.max_value = maxf(vm.session.engine.scheduler.threshold / float(Ruleset.TIME_SCALE), 1.0)
	ini.value = float(e["initiative"])
	ini.custom_minimum_size = Vector2(160, 8)
	ini.show_percentage = false
	var tex := TextureRect.new()
	tex.texture = PortraitProvider.texture(str(e["display_name"]))
	tex.custom_minimum_size = Vector2(64, 64)
	tex.expand_mode = TextureRect.EXPAND_IGNORE_SIZE
	tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	var res := ", ".join((e["resources"] as Dictionary).keys().map(func(k): return "%s %s" % [k, ReportDocument.num(e["resources"][k])]))
	var sts := ", ".join((e["statuses"] as Array).map(func(s): return "%s×%d" % [s["id"], s["stacks"]]))
	var info := UIKit.column([
		UIKit.label("%s [%s]%s" % [e["display_name"], e["team"], "" if bool(e["alive"]) else " ✝"]),
		hp, UIKit.label("%s / %s" % [ReportDocument.num(e["hp"]), ReportDocument.num(e["hp_max"])]), ini])
	if res != "":
		info.add_child(UIKit.note(res))
	if sts != "":
		info.add_child(UIKit.note(sts))
	var row := UIKit.row([tex, info])
	row.name = "card_" + str(e["id"])
	return row


func _show_inspector() -> void:
	UIKit.clear(inspect_box)
	var ins := vm.inspect()
	if ins.is_empty():
		return
	inspect_box.add_child(UIKit.header(t("viewer.inspect"), 3))
	inspect_box.add_child(UIKit.label(str(ins["text"])))
	if not (ins["detail"] as Array).is_empty():
		inspect_box.add_child(UIKit.table([t("col.field"), t("col.value")], ins["detail"].map(func(d): return [d[0], ReportDocument.num(d[1])])))
	inspect_box.add_child(UIKit.label(t("viewer.chain", [" ← ".join(ins["causal_chain"].map(func(c): return str(c["type"])))])))


func _process(delta: float) -> void:
	if vm == null or not vm.playing:
		return
	_accum += delta
	if _accum >= 0.12:
		_accum = 0.0
		vm.tick()
		update_view()
