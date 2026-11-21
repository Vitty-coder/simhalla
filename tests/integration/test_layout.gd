extends TestCase
## Auditoria de maquetacion SIN pantalla: ninguna pantalla ni la navegacion exigen mas ancho del que tiene un movil estrecho,
## los objetivos tactiles son >= 48 px y el contenido largo se ajusta. (No sustituye a una prueba visual real: ver docs/UI.md.)

const TMP := "user://_tests_layout"
const PHONE_W := 360.0


func _main() -> MainUI:
	var a := AppController.new("%s/l%d" % [TMP, Time.get_ticks_usec()])
	assert_eq(a.boot(), [])
	a.install_examples()
	var m: MainUI = (load("res://src/ui/main.tscn") as PackedScene).instantiate()
	m.app = a
	m.build_ui()
	return m


## Controles "hoja" cuyo minimo supera el ancho y cuyos hijos no lo superan (los culpables reales, no sus contenedores).
func _wide_culprits(root: Node, limit: float) -> Array:
	var out: Array = []
	for c in root.find_children("*", "Control", true, false):
		var ms := (c as Control).get_combined_minimum_size()
		if ms.x <= limit or c is ScrollContainer:
			continue
		var leaf := true
		for k in c.get_children():
			if k is Control and (k as Control).get_combined_minimum_size().x > limit:
				leaf = false
		if leaf:
			out.append("%s %s min.x=%d" % [c.get_class(), c.name, int(ms.x)])
	return out


func test_phone_width_every_screen_fits_without_horizontal_overflow() -> void:
	var m := _main()
	m.apply_layout(PHONE_W)
	assert_eq(m.layout_kind, "narrow")
	for s in AppController.SCREENS:
		m.app.go(s)
		var bad := _wide_culprits(m.screen_node, PHONE_W - 16.0)
		assert_eq(bad, [], "pantalla %s: controles que no caben en %d px" % [s, int(PHONE_W)])
	m.free()
	ContentLibrary._remove_tree(TMP)


func test_narrow_navigation_wraps_and_keeps_touch_targets() -> void:
	var m := _main()
	m.apply_layout(PHONE_W)
	assert_false(m.nav.vertical)
	assert_true(m.nav.get_combined_minimum_size().x <= PHONE_W, "la barra inferior debe poder partirse en filas: min.x=%d" % int(m.nav.get_combined_minimum_size().x))
	assert_eq(m.nav_buttons.size(), AppController.SCREENS.size(), "todas las pantallas son alcanzables desde la navegacion")
	for s in m.nav_buttons:
		var b: Button = m.nav_buttons[s]
		assert_true(b.custom_minimum_size.x >= UIKit.TOUCH_MIN and b.custom_minimum_size.y >= UIKit.TOUCH_MIN, s)
	m.apply_layout(1280.0)
	assert_true(m.nav.vertical)
	m.free()
	ContentLibrary._remove_tree(TMP)


## ¿Es un control interno de Godot (buscador del popup de un OptionButton, caja interna de un SpinBox)? Esos no los dimensiona la aplicacion.
func _is_internal(c: Node) -> bool:
	var p := c.get_parent()
	if p is SpinBox:
		return true
	while p != null:
		if p is Window:
			return true
		p = p.get_parent()
	return false


func test_interactive_controls_meet_the_touch_minimum() -> void:
	var m := _main()
	m.apply_layout(PHONE_W)
	for s in AppController.SCREENS:
		m.app.go(s)
		for c in m.screen_node.find_children("*", "BaseButton", true, false):
			if _is_internal(c):
				continue
			var b := c as BaseButton
			assert_true(b.custom_minimum_size.y >= UIKit.TOUCH_MIN or b.get_combined_minimum_size().y >= UIKit.TOUCH_MIN, "%s/%s es demasiado pequeno para tocarlo" % [s, b.name])
		for c in m.screen_node.find_children("*", "LineEdit", true, false):
			if _is_internal(c):
				continue
			assert_true((c as LineEdit).custom_minimum_size.y >= UIKit.TOUCH_MIN, "%s/%s" % [s, c.name])
	m.free()
	ContentLibrary._remove_tree(TMP)


func test_rows_wrap_instead_of_overflowing() -> void:
	var r := UIKit.row([UIKit.button("uno"), UIKit.button("dos")])
	assert_true(r is HFlowContainer)
	var long := UIKit.button("Un texto de boton muy largo que en un movil estrecho debe ajustarse en varias lineas en lugar de ensanchar la pantalla")
	assert_eq(long.autowrap_mode, TextServer.AUTOWRAP_WORD_SMART)
	assert_true(long.get_combined_minimum_size().x < 300.0, "el boton largo no fija un ancho enorme: %d" % int(long.get_combined_minimum_size().x))
	r.free()
	long.free()
