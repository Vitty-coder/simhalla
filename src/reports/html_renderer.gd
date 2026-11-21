class_name HtmlRenderer
extends RefCounted
## HTML (.html) AUTONOMO a partir de ReportDocument: estilos y graficas SVG en linea, sin CDN, sin red, SIN JavaScript.
## Todo texto/dato del modelo se ESCAPA (`& < > " '` y caracteres de control) para impedir inyeccion HTML; los atributos solo
## llevan valores generados aqui (clases fijas, numeros). Cabecera CSP restrictiva (`default-src 'none'`) como defensa adicional.
## Claro/oscuro segun el sistema; tablas con desplazamiento horizontal en pantallas estrechas.

const CSS := """
:root{color-scheme:light dark;--bg:#fbfbf9;--fg:#1d1d1b;--mut:#6b6b66;--line:#d9d8d2;--accent:#2a6f97;--bar:#2a6f97;--whisk:#1d1d1b;--note:#f0efe9}
@media (prefers-color-scheme:dark){:root{--bg:#161615;--fg:#ecece8;--mut:#a3a39b;--line:#34342f;--accent:#6fb3d9;--bar:#6fb3d9;--whisk:#ecece8;--note:#222220}}
*{box-sizing:border-box}body{margin:0;padding:0 16px 48px;background:var(--bg);color:var(--fg);font:15px/1.5 system-ui,-apple-system,"Segoe UI",Roboto,sans-serif}
main{max-width:1100px;margin:0 auto}h1{font-size:1.7rem;margin:1.4em 0 .4em}h2{font-size:1.25rem;margin:1.8em 0 .5em;border-bottom:1px solid var(--line);padding-bottom:.2em}h3{font-size:1.05rem}
.wrap{overflow-x:auto;margin:.6em 0 1em}table{border-collapse:collapse;min-width:60%;font-variant-numeric:tabular-nums}th,td{border:1px solid var(--line);padding:4px 8px;text-align:left;vertical-align:top;word-break:break-word}
th{background:var(--note)}td.r,th.r{text-align:right}.note{background:var(--note);border-left:3px solid var(--accent);padding:6px 10px;margin:.6em 0;color:var(--mut)}
svg{max-width:100%;height:auto;display:block;margin:.4em 0 1em}svg text{fill:var(--fg);font:12px system-ui,sans-serif}.bar{fill:var(--bar)}.whisk{stroke:var(--whisk);stroke-width:1.5;fill:none}.axis{stroke:var(--line)}
footer{margin-top:2.5em;color:var(--mut);font-size:.85rem;word-break:break-all}code{font-family:ui-monospace,Menlo,Consolas,monospace}
"""


static func esc(v: Variant) -> String:
	var s := str(v)
	var out := ""
	for i in s.length():
		var c := s[i]
		var code := s.unicode_at(i)
		if code < 32 and c != "\n" and c != "\t":
			continue
		if code == 127:
			continue
		match c:
			"&":
				out += "&amp;"
			"<":
				out += "&lt;"
			">":
				out += "&gt;"
			"\"":
				out += "&quot;"
			"'":
				out += "&#39;"
			_:
				out += c
	return out


static func render(doc: ReportDocument, report_hash: String = "") -> String:
	var h := "<!doctype html>\n<html lang=\"es\"><head><meta charset=\"utf-8\">\n"
	h += "<meta name=\"viewport\" content=\"width=device-width,initial-scale=1\">\n"
	h += "<meta http-equiv=\"Content-Security-Policy\" content=\"default-src 'none'; style-src 'unsafe-inline'; img-src data:\">\n"
	h += "<title>%s</title>\n<style>%s</style></head><body><main>\n" % [esc(doc.title), CSS]
	for b in doc.blocks:
		match b["t"]:
			"h":
				var lv := clampi(int(b["level"]), 1, 4)
				h += "<h%d>%s</h%d>\n" % [lv, esc(b["text"]), lv]
			"p":
				h += "<p>%s</p>\n" % esc(b["text"])
			"note":
				h += "<div class=\"note\">%s</div>\n" % esc(b["text"])
			"kv":
				h += "<div class=\"wrap\"><table><tbody>\n"
				for r in b["rows"]:
					h += "<tr><th>%s</th><td>%s</td></tr>\n" % [esc(r[0]), esc(r[1])]
				h += "</tbody></table></div>\n"
			"table":
				var al: Array = b.get("align", [])
				h += "<div class=\"wrap\"><table><thead><tr>"
				for i in (b["cols"] as Array).size():
					h += "<th%s>%s</th>" % [" class=\"r\"" if i < al.size() and al[i] == "r" else "", esc(b["cols"][i])]
				h += "</tr></thead><tbody>\n"
				for r in b["rows"]:
					h += "<tr>"
					for i in (r as Array).size():
						h += "<td%s>%s</td>" % [" class=\"r\"" if i < al.size() and al[i] == "r" else "", esc(r[i])]
					h += "</tr>\n"
				h += "</tbody></table></div>\n"
			"bars":
				h += _bars(b)
			"hist":
				h += _hist(b)
			"list":
				h += "<ul>\n" + "".join((b["items"] as Array).map(func(i): return "<li>%s</li>\n" % esc(i))) + "</ul>\n"
	if report_hash != "":
		h += "<footer>Huella del informe (SHA-256 del modelo JSON sin <code>measurement</code>): <code>%s</code></footer>\n" % esc(report_hash)
	return h + "</main></body></html>\n"


static func _n(v: float) -> String:
	return "%.1f" % v


static func _bars(b: Dictionary) -> String:
	var items: Array = b["items"]
	if items.is_empty():
		return ""
	var unit := str(b.get("unit", ""))
	var mx := float(b.get("max", 0.0))
	if mx <= 0.0:
		for it in items:
			mx = maxf(mx, float(it["value"]) if it["value"] != null else 0.0)
		if mx <= 0.0:
			mx = 1.0
	var row_h := 24
	var lw := 200.0
	var cw := 360.0
	var height := items.size() * row_h + 30
	var s := "<p><strong>%s</strong></p>\n<svg role=\"img\" aria-label=\"%s\" viewBox=\"0 0 700 %d\" width=\"700\" height=\"%d\">\n" % [esc(b["title"]), esc(b["title"]), height, height]
	for i in items.size():
		var it: Dictionary = items[i]
		var y := 6 + i * row_h
		var label := str(it["label"])
		s += "<text x=\"%s\" y=\"%d\" text-anchor=\"end\">%s</text>\n" % [_n(lw - 8.0), y + 14, esc(label.substr(0, 28) + ("…" if label.length() > 28 else ""))]
		if it["value"] == null:
			s += "<text x=\"%s\" y=\"%d\">—</text>\n" % [_n(lw), y + 14]
			continue
		var w := clampf(float(it["value"]) / mx, 0.0, 1.0) * cw
		s += "<rect class=\"bar\" x=\"%s\" y=\"%d\" width=\"%s\" height=\"14\" rx=\"2\"/>\n" % [_n(lw), y, _n(w)]
		if it.get("lo", null) != null:
			var x1 := lw + clampf(float(it["lo"]) / mx, 0.0, 1.0) * cw
			var x2 := lw + clampf(float(it["hi"]) / mx, 0.0, 1.0) * cw
			s += "<path class=\"whisk\" d=\"M%s %d H%s M%s %d v10 M%s %d v10\"/>\n" % [_n(x1), y + 7, _n(x2), _n(x1), y + 2, _n(x2), y + 2]
		var txt := ReportDocument.pct(it["value"]) if unit == "%" else ReportDocument.num(it["value"])
		s += "<text x=\"%s\" y=\"%d\">%s</text>\n" % [_n(lw + cw + 12.0), y + 14, esc(txt)]
	s += "<line class=\"axis\" x1=\"%s\" y1=\"2\" x2=\"%s\" y2=\"%d\"/>\n" % [_n(lw), _n(lw), height - 24]
	return s + "</svg>\n"


static func _hist(b: Dictionary) -> String:
	var bins: Array = b["bins"]
	if bins.is_empty():
		return ""
	var top := 1
	for bin in bins:
		top = maxi(top, int(bin["count"]))
	var bw := 44.0
	var width := bins.size() * bw + 60.0
	var s := "<p><strong>%s</strong></p>\n<svg role=\"img\" aria-label=\"%s\" viewBox=\"0 0 %s 170\" width=\"%s\" height=\"170\">\n" % [esc(b["title"]), esc(b["title"]), _n(width), _n(width)]
	for i in bins.size():
		var c := int(bins[i]["count"])
		var hgt := float(c) / float(top) * 110.0
		var x := 30.0 + i * bw
		s += "<rect class=\"bar\" x=\"%s\" y=\"%s\" width=\"%s\" height=\"%s\" rx=\"2\"/>\n" % [_n(x + 2.0), _n(130.0 - hgt), _n(bw - 4.0), _n(hgt)]
		s += "<text x=\"%s\" y=\"%s\" text-anchor=\"middle\">%d</text>\n" % [_n(x + bw / 2.0), _n(124.0 - hgt), c]
		s += "<text x=\"%s\" y=\"150\" text-anchor=\"middle\">%s</text>\n" % [_n(x + bw / 2.0), esc(ReportDocument.num(bins[i]["lo"], 1))]
	s += "<line class=\"axis\" x1=\"28\" y1=\"130\" x2=\"%s\" y2=\"130\"/>\n" % _n(width - 20.0)
	return s + "</svg>\n"
