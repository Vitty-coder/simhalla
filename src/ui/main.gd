class_name MainUI
extends Control
## Interfaz principal 2D abstracta y ADAPTABLE: barra lateral en pantallas anchas (PC) y barra inferior en estrechas (movil/Android),
## controles de al menos 48 px (tactil) y teclado/raton en PC. Toda la logica vive en AppController y sus modelos; esta escena solo
## navega, presenta y delega. Los textos salen de LocaleService (claves estables, español inicial).
##
## Para pruebas/automatizacion: asignar `app` ANTES de anadir el nodo al arbol; `apply_layout(ancho)` fuerza el disenio.

const NARROW_WIDTH := 720.0


static func screen_class(name: String) -> GDScript:
	match name:
		"library":
			return LibraryScreen
		"import":
			return ImportScreen
		"duel":
			return DuelScreen
		"viewer":
			return ViewerScreen
		"batch":
			return BatchScreen
		"reports":
			return ReportsScreen
		"rules":
			return RulesScreen
		"debug":
			return DebugScreen
		"platform":
			return PlatformScreen
		"settings":
			return SettingsScreen
	return null


var app: AppController
var layout_kind: String = "wide"
var root_box: BoxContainer
var nav: FlowContainer
var content: MarginContainer
var status: Label
var screen_node: BaseScreen = null
var nav_buttons: Dictionary = {}


var _built: bool = false


func _ready() -> void:
	build_ui()


## Construye la interfaz (idempotente). Es lo que hace `_ready`; las pruebas headless lo invocan directamente porque el arbol de
## escenas aun no esta inicializado durante `_init` del ejecutor.
func build_ui() -> void:
	if _built:
		return
	_built = true
	if app == null:
		app = AppController.new()
		app.boot()
	if OS.get_cmdline_user_args().has("--selftest"):
		_selftest()
		return
	LocaleService.load_all()
	theme = _make_theme()
	set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box = BoxContainer.new()
	root_box.set_anchors_preset(Control.PRESET_FULL_RECT)
	root_box.add_theme_constant_override("separation", 6)
	add_child(root_box)
	nav = FlowContainer.new() # en estrecho se parte en filas (10 botones no caben en una linea de 360 px)
	nav.add_theme_constant_override("h_separation", 4)
	nav.add_theme_constant_override("v_separation", 4)
	root_box.add_child(nav)
	var right := VBoxContainer.new()
	right.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	right.size_flags_vertical = Control.SIZE_EXPAND_FILL
	root_box.add_child(right)
	status = Label.new()
	status.name = "status_bar"
	status.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	right.add_child(status)
	content = MarginContainer.new()
	content.size_flags_vertical = Control.SIZE_EXPAND_FILL
	content.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for side in ["left", "right", "top", "bottom"]:
		content.add_theme_constant_override("margin_" + side, 8)
	right.add_child(content)
	for s in AppController.SCREENS:
		var b := Button.new()
		b.name = "nav_" + s
		b.toggle_mode = false
		b.custom_minimum_size = Vector2(UIKit.TOUCH_MIN, UIKit.TOUCH_MIN)
		b.pressed.connect(func(): app.go(s))
		nav.add_child(b)
		nav_buttons[s] = b
	app.screen_changed.connect(_show)
	app.settings_changed.connect(func():
		apply_layout(size.x if size.x > 0.0 else 1280.0)
		update_status()
		if app.screen != "settings": # la pantalla de ajustes se refresca a si misma (conserva su mensaje)
			_show(app.screen))
	resized.connect(func(): apply_layout(size.x))
	apply_layout(size.x if size.x > 0.0 else 1280.0)
	_show(app.screen)


func _make_theme() -> Theme:
	var th := Theme.new()
	th.default_font_size = 20 if DisplayServer.is_touchscreen_available() else 18
	th.set_constant("separation", "VBoxContainer", 6)
	return th


## Disenio segun el ancho: barra lateral (ancho) o inferior (estrecho). Los botones usan texto completo o corto.
func apply_layout(width: float) -> void:
	var narrow := width < NARROW_WIDTH
	layout_kind = "narrow" if narrow else "wide"
	if root_box == null:
		return
	root_box.vertical = narrow
	nav.vertical = not narrow
	if narrow:
		root_box.move_child(nav, root_box.get_child_count() - 1)
	else:
		root_box.move_child(nav, 0)
	for s in nav_buttons:
		var b: Button = nav_buttons[s]
		b.text = LocaleService.t("nav.%s.short" % s) if narrow else LocaleService.t("nav." + s)
		b.tooltip_text = LocaleService.t("nav." + s)
		b.size_flags_horizontal = Control.SIZE_EXPAND_FILL if narrow else Control.SIZE_FILL
	nav.custom_minimum_size = Vector2(0, UIKit.TOUCH_MIN + 6) if narrow else Vector2(190, 0)


func _show(screen: String) -> void:
	if screen_node != null:
		content.remove_child(screen_node)
		screen_node.queue_free()
		screen_node = null
	var cls: GDScript = screen_class(screen)
	if cls == null:
		return
	screen_node = cls.new()
	content.add_child(screen_node)
	screen_node.setup(app)
	for s in nav_buttons:
		(nav_buttons[s] as Button).disabled = (s == screen)
	update_status()


## Linea de estado permanente: modo libre/reglamentado y perfil (con aviso de ilustrativo).
func update_status() -> void:
	var prof := app.profile()
	status.text = LocaleService.t("ctx.mode_profile", [app.mode_label(), prof.id, prof.version]) + ("   ⚠ " + LocaleService.t("balance.illustrative.short") if prof.illustrative else "")


## Modo `--selftest` (argumento de usuario tras `--`): ejecuta el diagnostico de plataforma sin interfaz, escribe el informe y sale con
## codigo 0 (compatible) o 1. Sirve para validar un EXPORTADO (el .pck/binario) en una carpeta vacia, es decir, que el filtro de exportacion
## incluye todo lo necesario.
func _selftest() -> void:
	var pc := PlatformCheck.new({"bench_ms": 300})
	pc.run_all()
	print(pc.to_markdown())
	PlatformScreen.save_report(app, pc)
	var code := 0 if pc.failed() == 0 else 1
	var tree := get_tree()
	if tree != null:
		tree.quit(code)
