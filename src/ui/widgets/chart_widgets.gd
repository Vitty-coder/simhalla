class_name ChartBars
extends Control
## Grafica de barras horizontales con intervalos (se dibuja con `_draw`; sin texturas ni recursos externos).
## items: [{label, value (0..max) | null, lo?, hi?}], unit "%" => formatea como porcentaje.

var items: Array = []
var unit: String = ""
var max_value: float = 1.0
const ROW := 26


func set_data(its: Array, u: String = "", mx: float = 0.0) -> void:
	items = its
	unit = u
	max_value = mx
	if max_value <= 0.0:
		for it in its:
			max_value = maxf(max_value, float(it["value"]) if it["value"] != null else 0.0)
		if max_value <= 0.0:
			max_value = 1.0
	custom_minimum_size = Vector2(320, ROW * its.size() + 8)
	queue_redraw()


func _draw() -> void:
	var font := get_theme_default_font()
	var fs := 14
	var lw := minf(size.x * 0.34, 200.0)
	var cw := maxf(size.x - lw - 90.0, 40.0)
	for i in items.size():
		var it: Dictionary = items[i]
		var y := 4.0 + i * ROW
		draw_string(font, Vector2(2, y + 16), str(it["label"]).substr(0, 24), HORIZONTAL_ALIGNMENT_LEFT, lw - 6, fs, Color(0.9, 0.9, 0.88))
		if it["value"] == null:
			draw_string(font, Vector2(lw, y + 16), "—", HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.7, 0.7, 0.7))
			continue
		var w := clampf(float(it["value"]) / max_value, 0.0, 1.0) * cw
		draw_rect(Rect2(lw, y + 2, w, 16), Color(0.42, 0.7, 0.85))
		if it.get("lo", null) != null:
			var x1 := lw + clampf(float(it["lo"]) / max_value, 0.0, 1.0) * cw
			var x2 := lw + clampf(float(it["hi"]) / max_value, 0.0, 1.0) * cw
			draw_line(Vector2(x1, y + 10), Vector2(x2, y + 10), Color(1, 1, 1), 1.5)
			draw_line(Vector2(x1, y + 4), Vector2(x1, y + 16), Color(1, 1, 1), 1.5)
			draw_line(Vector2(x2, y + 4), Vector2(x2, y + 16), Color(1, 1, 1), 1.5)
		var txt := ReportDocument.pct(it["value"]) if unit == "%" else ReportDocument.num(it["value"])
		draw_string(font, Vector2(lw + cw + 8, y + 16), txt, HORIZONTAL_ALIGNMENT_LEFT, -1, fs, Color(0.9, 0.9, 0.88))
