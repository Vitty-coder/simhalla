class_name UIKit
extends RefCounted
## Utilidades para construir controles adaptables (tactil en Android, teclado/raton en PC): tamano minimo de pulsacion,
## etiquetas con ajuste de linea, tablas, encabezados y secciones. Todo el texto pasa por LocaleService (claves estables).

const TOUCH_MIN := 48

static func t(key: String, args: Array = []) -> String:
	return LocaleService.t(key, args)


static func label(text: String, wrap: bool = true) -> Label:
	var l := Label.new()
	l.text = text
	if wrap:
		l.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		l.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return l


static func header(text: String, level: int = 2) -> Label:
	var l := label(text)
	l.add_theme_font_size_override("font_size", {1: 26, 2: 21, 3: 18}.get(level, 18))
	l.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95))
	return l


static func note(text: String) -> Label:
	var l := label(text)
	l.add_theme_color_override("font_color", Color(0.72, 0.72, 0.66))
	return l


static func warn(text: String) -> Label:
	var l := label(text)
	l.add_theme_color_override("font_color", Color(0.98, 0.78, 0.35))
	return l


static func error(text: String) -> Label:
	var l := label(text)
	l.add_theme_color_override("font_color", Color(0.98, 0.45, 0.42))
	return l


static func button(text: String, callback: Callable = Callable()) -> Button:
	var b := Button.new()
	b.text = text
	b.custom_minimum_size = Vector2(TOUCH_MIN, TOUCH_MIN)
	b.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART # textos largos (p. ej. entradas de biblioteca) se ajustan en lugar de ensanchar
	if callback.is_valid():
		b.pressed.connect(callback)
	return b


## Fila de controles que se PARTE en varias lineas si no caben (movil estrecho) en vez de desbordar la pantalla.
static func row(children: Array = []) -> HFlowContainer:
	var h := HFlowContainer.new()
	h.add_theme_constant_override("h_separation", 8)
	h.add_theme_constant_override("v_separation", 6)
	for c in children:
		h.add_child(c)
	return h


static func column(children: Array = []) -> VBoxContainer:
	var v := VBoxContainer.new()
	v.add_theme_constant_override("separation", 6)
	for c in children:
		v.add_child(c)
	return v


static func option(items: Array, selected: Variant = null) -> OptionButton:
	var o := OptionButton.new()
	o.custom_minimum_size = Vector2(120, TOUCH_MIN)
	for it in items:
		o.add_item(str(it))
	if selected != null:
		var idx := items.find(selected)
		if idx >= 0:
			o.select(idx)
	return o


static func line_edit(text: String = "", placeholder: String = "") -> LineEdit:
	var e := LineEdit.new()
	e.text = text
	e.placeholder_text = placeholder
	e.custom_minimum_size = Vector2(120, TOUCH_MIN)
	e.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	return e


static func clear(node: Node) -> void:
	for c in node.get_children():
		node.remove_child(c)
		c.queue_free()


## Tabla simple: cabecera + filas de texto. Se desplaza horizontalmente si no cabe.
static func table(cols: Array, rows: Array, align_right: Array = []) -> Control:
	var sc := ScrollContainer.new()
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_AUTO
	sc.vertical_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var g := GridContainer.new()
	g.columns = maxi(cols.size(), 1)
	g.add_theme_constant_override("h_separation", 14)
	g.add_theme_constant_override("v_separation", 3)
	for c in cols:
		var h := Label.new()
		h.text = str(c)
		h.add_theme_color_override("font_color", Color(0.55, 0.78, 0.95))
		g.add_child(h)
	for r in rows:
		for i in (r as Array).size():
			var l := Label.new()
			l.text = str(r[i])
			if align_right.has(i):
				l.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
			g.add_child(l)
	sc.add_child(g)
	return sc


## Cuerpo desplazable para una pantalla.
static func scroll_body() -> Array:
	var sc := ScrollContainer.new()
	sc.size_flags_vertical = Control.SIZE_EXPAND_FILL
	sc.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	sc.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	var body := VBoxContainer.new()
	body.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	body.add_theme_constant_override("separation", 8)
	sc.add_child(body)
	return [sc, body]
