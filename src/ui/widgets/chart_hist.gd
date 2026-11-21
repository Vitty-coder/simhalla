class_name ChartHist
extends Control
## Histograma de columnas (`_draw`). bins: [{lo, hi, count}].

var bins: Array = []


func set_data(b: Array) -> void:
	bins = b
	custom_minimum_size = Vector2(max(320, 36 * b.size() + 40), 150)
	queue_redraw()


func _draw() -> void:
	if bins.is_empty():
		return
	var font := get_theme_default_font()
	var top := 1
	for b in bins:
		top = maxi(top, int(b["count"]))
	var bw := (size.x - 30.0) / float(bins.size())
	for i in bins.size():
		var h := float(bins[i]["count"]) / float(top) * 90.0
		var x := 24.0 + i * bw
		draw_rect(Rect2(x + 2, 110.0 - h, maxf(bw - 4.0, 1.0), h), Color(0.42, 0.7, 0.85))
		draw_string(font, Vector2(x, 106.0 - h), str(bins[i]["count"]), HORIZONTAL_ALIGNMENT_LEFT, bw, 12, Color(0.9, 0.9, 0.88))
		draw_string(font, Vector2(x, 128), ReportDocument.num(bins[i]["lo"], 1), HORIZONTAL_ALIGNMENT_LEFT, bw, 11, Color(0.75, 0.75, 0.72))
	draw_line(Vector2(22, 110), Vector2(size.x - 6, 110), Color(0.5, 0.5, 0.5))
