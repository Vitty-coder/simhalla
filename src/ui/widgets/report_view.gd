class_name ReportView
extends VBoxContainer
## Pinta de forma NATIVA un ReportDocument (el mismo documento que consumen Markdown y HTML): titulos, notas, tablas,
## graficas de barras con intervalos, histogramas y listas. Solo presentacion.

func show_document(doc: ReportDocument) -> void:
	UIKit.clear(self)
	for b in doc.blocks:
		match b["t"]:
			"h":
				add_child(UIKit.header(str(b["text"]), int(b["level"])))
			"p":
				add_child(UIKit.label(str(b["text"])))
			"note":
				add_child(UIKit.note(str(b["text"])))
			"kv":
				add_child(UIKit.table(["", ""], b["rows"]))
			"table":
				add_child(UIKit.table(b["cols"], b["rows"], _right_cols(b.get("align", []))))
			"bars":
				add_child(UIKit.label(str(b["title"])))
				var cb := ChartBars.new()
				cb.set_data(b["items"], str(b.get("unit", "")), float(b.get("max", 0.0)))
				add_child(cb)
			"hist":
				add_child(UIKit.label(str(b["title"])))
				var ch := ChartHist.new()
				ch.set_data(b["bins"])
				add_child(ch)
			"list":
				for i in b["items"]:
					add_child(UIKit.label("• " + str(i)))


static func _right_cols(align: Array) -> Array:
	var out: Array = []
	for i in align.size():
		if align[i] == "r":
			out.append(i)
	return out
