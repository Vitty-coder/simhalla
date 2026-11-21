class_name LibraryModel
extends RefCounted
## Modelo de la pantalla Biblioteca: busqueda, filtros por tipo, versiones y detalle de un paquete (PJ, habilidades, IA) con
## validacion de integridad, dependencias, scripts, coste calculado frente al presupuesto y registros que lo usan.
## Sin nodos: la interfaz solo presenta lo que devuelve.

var app: AppController


func _init(a: AppController) -> void:
	app = a


## [{id, version, type, hash, name, versions, latest}] filtrado por texto (id o nombre) y tipo (`character|abilities|ai`).
func entries(filter: Dictionary = {}) -> Array:
	var out: Array = []
	var q := str(filter.get("query", "")).to_lower()
	var want_type := str(filter.get("type", ""))
	var by_id := {}
	for e in app.storage.library.list():
		var vs := app.storage.library.versions(str(e["id"]))
		var lp := app.storage.library.load_package(str(e["id"]), str(e["version"]))
		var name := str(lp["manifest"].get("name", e["id"])) if (lp["errors"] as Array).is_empty() else str(e["id"])
		if want_type != "" and str(e["type"]) != want_type:
			continue
		if q != "" and not (str(e["id"]).to_lower().contains(q) or name.to_lower().contains(q)):
			continue
		out.append({"id": e["id"], "version": e["version"], "type": e["type"], "hash": e["hash"], "name": name, "versions": vs, "latest": vs.back() == e["version"],
			"valid": (lp["errors"] as Array).is_empty()})
		by_id[e["id"]] = true
	return out


func versions_of(id: String) -> Array:
	return app.storage.library.versions(id)


## Datos de un paquete de personaje compuestos como entidad (con id/team para valorarlo). {"ok","data","errors"}.
func compose(id: String, version: String) -> Dictionary:
	var lp := app.storage.library.load_package(id, version)
	if not (lp["errors"] as Array).is_empty():
		return {"ok": false, "data": {}, "errors": lp["errors"]}
	if str(lp["manifest"].get("type", "")) != "character":
		return {"ok": false, "data": {}, "errors": ["[tipo] %s@%s no es un personaje" % [id, version]]}
	var comp := EntityComposer.compose(lp["parsed"], lp["manifest"], app.storage.library, PackageSource.scripts_of(lp["files"]))
	if not (comp["errors"] as Array).is_empty():
		return {"ok": false, "data": {}, "errors": comp["errors"]}
	var d: Dictionary = comp["data"]
	d["id"] = id
	d["team"] = "lib"
	return {"ok": true, "data": d, "errors": [], "files": lp["files"], "deps": comp["deps"]}


## Detalle de un paquete. cost: {"mode","budget","profile"} opcional (por defecto, los ajustes).
func detail(id: String, version: String, cost_opts: Dictionary = {}) -> Dictionary:
	var lib := app.storage.library
	if not lib.has(id, version):
		return {"ok": false, "errors": ["[no_encontrado] %s@%s" % [id, version]]}
	var lp := lib.load_package(id, version)
	var out := {"ok": (lp["errors"] as Array).is_empty(), "id": id, "version": version, "versions": lib.versions(id), "errors": lp["errors"],
		"integrity": "ok" if (lp["errors"] as Array).is_empty() else "alterado", "hash": lp["hash"], "manifest": lp["manifest"],
		"used_by": app.storage.references_to("package", id, version)}
	if not bool(out["ok"]):
		return out
	out["files"] = lp["files"].keys()
	if str(lp["manifest"].get("type", "")) == "character":
		var c := compose(id, version)
		if not bool(c["ok"]):
			out["compose_errors"] = c["errors"]
			return out
		var d: Dictionary = c["data"]
		out["character"] = {"name": d.get("name", id), "tags": d.get("tags", []), "stats": d.get("stats", {}), "resources": d.get("resources", {}),
			"abilities": (d.get("abilities", []) as Array).map(func(a): return {"id": a.get("id", ""), "name": a.get("name", a.get("id", "")), "action_type": a.get("action_type", "main"),
				"cost": a.get("cost", {}), "cooldown": a.get("cooldown", null), "tags": a.get("tags", [])}),
			"ai": d.get("ai", {}), "artifact": d.get("artifact", {}).get("id", "") if d.get("artifact", null) is Dictionary else "",
			"scripts": (d.get("scripts", {}) as Dictionary).keys(), "basic_attack": d.get("basic_attack", true)}
		out["dependencies"] = c["deps"]
		var res := app.cost_report(d, cost_opts)
		out["cost"] = res
		out["portrait"] = PortraitProvider.load_image(str(d.get("name", id)), lp["files"])["from_package"]
	return out


func remove(id: String, version: String, force: bool = false) -> String:
	return app.storage.remove_package(id, version, force)


## Historial de operaciones (mas reciente al final). `limit` 0 = todo.
func history(limit: int = 0) -> Array:
	return app.storage.history(limit)


## Exporta paquetes (lista "id@version"; vacia = toda la biblioteca) a un bundle portable. Devuelve el resultado de BundleIO.
func export_library(path: String, selection: Array = []) -> Dictionary:
	return BundleIO.export_library(app.storage, path, selection)
