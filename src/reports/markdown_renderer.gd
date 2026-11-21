class_name MarkdownRenderer
extends RefCounted
## Markdown (.md) legible por personas e IAs, a partir de ReportDocument. Todo texto del modelo se ESCAPA: las celdas no pueden
## romper la tabla (`|`, saltos de linea), ni inyectar HTML (`<`, `>`, `&`) ni formato (acentos graves, `[`, `]`).

static func esc(v: Variant) -> String:
	var s := str(v)
	var out := ""
	for i in s.length():
		var c := s[i]
		var code := s.unicode_at(i)
		if c == "\n" or c == "\r" or c == "\t":
			out += " "
		elif code < 32 or code == 127:
			continue
		elif c == "|":
			out += "\\|"
		elif c == "<":
			out += "&lt;"
		elif c == ">":
			out += "&gt;"
		elif c == "&":
			out += "&amp;"
		elif c == "`":
			out += "'"
		elif c == "[" or c == "]" or c == "*" or c == "_" or c == "\\":
			out += "\\" + c
		else:
			out += c
	return out


static func render(doc: ReportDocument, report_hash: String = "") -> String:
	var out := ""
	for b in doc.blocks:
		match b["t"]:
			"h":
				out += "\n%s %s\n\n" % ["#".repeat(int(b["level"])), esc(b["text"])]
			"p":
				out += "%s\n\n" % esc(b["text"])
			"note":
				out += "> %s\n\n" % esc(b["text"])
			"kv":
				out += "| Campo | Valor |\n|---|---|\n"
				for r in b["rows"]:
					out += "| %s | %s |\n" % [esc(r[0]), esc(r[1])]
				out += "\n"
			"table":
				var cols: Array = b["cols"]
				var al: Array = b.get("align", [])
				out += "| " + " | ".join(cols.map(func(c): return esc(c))) + " |\n"
				out += "|" + "|".join(range(cols.size()).map(func(i): return "---:" if i < al.size() and al[i] == "r" else "---")) + "|\n"
				for r in b["rows"]:
					out += "| " + " | ".join((r as Array).map(func(c): return esc(c))) + " |\n"
				out += "\n"
			"bars":
				out += "**%s**\n\n| Etiqueta | Valor | Intervalo | |\n|---|---:|---|---|\n" % esc(b["title"])
				var mx := float(b.get("max", 0.0))
				if mx <= 0.0:
					for it in b["items"]:
						mx = maxf(mx, float(it["value"]) if it["value"] != null else 0.0)
				for it in b["items"]:
					var v: Variant = it["value"]
					var n := 0 if v == null or mx <= 0.0 else int(round(clampf(float(v) / mx, 0.0, 1.0) * 20.0))
					var interval := "—" if it.get("lo", null) == null else "[%s, %s]" % [_fmt(it["lo"], b["unit"]), _fmt(it["hi"], b["unit"])]
					out += "| %s | %s | %s | %s |\n" % [esc(it["label"]), _fmt(v, b["unit"]), interval, "█".repeat(n) + "░".repeat(20 - n)]
				out += "\n"
			"hist":
				out += "**%s**\n\n| Intervalo | n | |\n|---|---:|---|\n" % esc(b["title"])
				var top := 0
				for bin in b["bins"]:
					top = maxi(top, int(bin["count"]))
				for bin in b["bins"]:
					var n2 := 0 if top == 0 else int(round(float(bin["count"]) / float(top) * 20.0))
					out += "| %s – %s | %d | %s |\n" % [ReportDocument.num(bin["lo"]), ReportDocument.num(bin["hi"]), int(bin["count"]), "█".repeat(n2)]
				out += "\n"
			"list":
				for i in b["items"]:
					out += "- %s\n" % esc(i)
				out += "\n"
	if report_hash != "":
		out += "---\nHuella del informe (SHA-256 del modelo JSON sin `measurement`): `%s`\n" % report_hash
	return out


static func _fmt(v: Variant, unit: String) -> String:
	if v == null:
		return "—"
	return ReportDocument.pct(v) if unit == "%" else ReportDocument.num(v)
