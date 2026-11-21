class_name BaseScreen
extends VBoxContainer
## Base de las pantallas: recibe el AppController, construye su contenido en `refresh()` (reconstruccion completa, simple y
## sin estado oculto) y delega TODAS las acciones en los modelos de aplicacion. Nunca ejecuta reglas de combate.

var app: AppController
var body: VBoxContainer


func setup(a: AppController) -> void:
	app = a
	size_flags_vertical = Control.SIZE_EXPAND_FILL
	size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var parts := UIKit.scroll_body()
	add_child(parts[0])
	body = parts[1]
	refresh()


func refresh() -> void:
	UIKit.clear(body)
	build()


func build() -> void:
	pass


func t(key: String, args: Array = []) -> String:
	return LocaleService.t(key, args)


## Linea de contexto siempre visible junto a costes: modo libre/reglamentado, perfil y aviso de perfil ilustrativo.
func context_line() -> Control:
	var prof := app.profile()
	var c := UIKit.column()
	c.add_child(UIKit.label(t("ctx.mode_profile", [app.mode_label(), prof.id, prof.version])))
	if prof.illustrative:
		c.add_child(UIKit.warn(t("balance.illustrative")))
	return c
