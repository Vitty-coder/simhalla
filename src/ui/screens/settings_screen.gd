class_name SettingsScreen
extends BaseScreen
## Ajustes: idioma, modo por defecto (libre vs reglamentado explicado), presupuesto, perfil, hilos y detalle del historial.

var message: String = ""


func build() -> void:
	body.add_child(UIKit.header(t("nav.settings"), 1))
	var s := app.settings()
	var loc := UIKit.option(LocaleService.LOCALES, str(s["locale"]))
	loc.name = "locale_option"
	var modes := ["free", "regulated"]
	var mo := UIKit.option(modes.map(func(m): return t("mode." + m)), null)
	mo.select(modes.find(str(s["default_mode"])))
	mo.name = "mode_setting"
	var prof := app.profile()
	var budgets: Array = prof.budgets.keys()
	var bo := UIKit.option(budgets, str(s["default_budget"]))
	var workers := SpinBox.new()
	workers.min_value = 0
	workers.max_value = BatchRunner.MAX_WORKERS
	workers.value = int(s["workers"])
	workers.custom_minimum_size.y = UIKit.TOUCH_MIN
	var hist_modes := ["none", "summary", "full"]
	var ho := UIKit.option(hist_modes, str(s["history"]))
	body.add_child(UIKit.row([UIKit.label(t("settings.locale")), loc]))
	body.add_child(UIKit.row([UIKit.label(t("settings.mode")), mo]))
	body.add_child(UIKit.note(t("settings.mode_help")))
	body.add_child(UIKit.row([UIKit.label(t("settings.budget")), bo]))
	body.add_child(UIKit.row([UIKit.label(t("settings.workers")), workers]))
	body.add_child(UIKit.row([UIKit.label(t("settings.history")), ho]))
	var save := UIKit.button(t("settings.save"), func():
		var errs := app.save_settings({"locale": LocaleService.LOCALES[loc.selected], "default_mode": modes[mo.selected], "default_budget": budgets[bo.selected] if not budgets.is_empty() else str(s["default_budget"]),
			"workers": int(workers.value), "history": hist_modes[ho.selected]})
		message = t("settings.saved") if errs.is_empty() else "; ".join(errs)
		refresh())
	save.name = "save_settings_btn"
	body.add_child(save)
	if message != "":
		body.add_child(UIKit.label(message))
	var ex := UIKit.button(t("library.install_examples"), func():
		var r := app.install_examples()
		message = t("settings.examples", [r["installed"].size(), r["present"].size(), r["errors"].size()])
		refresh())
	ex.name = "settings_examples_btn"
	body.add_child(ex)
	body.add_child(UIKit.button(t("nav.platform"), func(): app.go("platform")))
	body.add_child(UIKit.note(t("settings.storage", [ProjectSettings.globalize_path(app.storage.root)])))
