class_name EntityComposer
extends RefCounted
## Compone los datos de una entidad a partir de los archivos de un paquete de
## personaje y de sus dependencias resueltas en la biblioteca.
##
## No ejecuta nada: solo fusiona datos. Resuelve `imports` (habilidades de
## paquetes "abilities") y `ai_ref` (estrategia de un paquete "ai"). Cada paquete
## usado debe estar declarado en `manifest.dependencies`.

## `parsed`: {archivo: json}. Devuelve {"data","errors","warnings","deps":[{id,version,hash}]}.
static func compose(parsed: Dictionary, manifest: Dictionary, library: ContentLibrary, scripts: Dictionary = {}) -> Dictionary:
	var errs: Array = []
	var warns: Array = []
	var deps: Array = []
	var resolved := {} # package id -> package cargado
	var declared := {}
	for d in manifest.get("dependencies", []):
		declared[str(d["id"])] = str(d["version"])

	# Todas las dependencias declaradas deben resolverse y ser de un tipo permitido.
	var used := {}
	for dep_id in declared:
		var e := library.resolve(dep_id, declared[dep_id])
		if e.is_empty():
			errs.append("manifest.json: dependencia '%s' (%s) no encontrada en la biblioteca" % [dep_id, declared[dep_id]])
			continue
		if not ["abilities", "ai"].has(e["type"]):
			errs.append("manifest.json: la dependencia '%s' es de tipo '%s' (solo se admiten 'abilities' y 'ai')" % [dep_id, e["type"]])
			continue
		var pkg := library.load_package(dep_id, e["version"])
		if not pkg["errors"].is_empty():
			errs.append_array(pkg["errors"])
			continue
		resolved[dep_id] = pkg
	if not errs.is_empty():
		return {"data": {}, "errors": errs, "warnings": warns, "deps": deps}

	var ch: Dictionary = parsed.get("character.json", {})
	var data := {"id": str(manifest.get("id", "")), "name": str(ch.get("name", ""))}
	for k in ["tags", "stats", "basic_attack", "counts_for_victory"]:
		if ch.has(k):
			data[k] = (ch[k] as Variant).duplicate(true) if (ch[k] is Dictionary or ch[k] is Array) else ch[k]
	if parsed.has("resources.json"):
		data["resources"] = parsed["resources.json"]["resources"].duplicate(true)
	var abilities: Array = []
	var seen := {}
	if parsed.has("abilities.json"):
		for a in parsed["abilities.json"]["abilities"]:
			abilities.append(a.duplicate(true))
			seen[str(a["id"])] = "propia"
	for imp in ch.get("imports", []):
		var pid := str(imp["package"])
		used[pid] = true
		if not declared.has(pid):
			errs.append("character.json: imports usa '%s', que no esta declarada en manifest.dependencies" % pid)
			continue
		if not resolved[pid]["manifest"].get("type", "") == "abilities":
			errs.append("character.json: imports: '%s' no es un paquete de habilidades" % pid)
			continue
		if not SemVer.satisfies(resolved[pid]["manifest"]["version"], str(imp["version"])):
			errs.append("character.json: imports '%s': la version resuelta %s no cumple '%s'" % [pid, resolved[pid]["manifest"]["version"], str(imp["version"])])
			continue
		var lib_abilities: Array = resolved[pid]["parsed"]["abilities.json"]["abilities"]
		for want in imp["abilities"]:
			var found: Variant = null
			for a in lib_abilities:
				if str(a["id"]) == str(want):
					found = a
			if found == null:
				errs.append("character.json: el paquete '%s' no define la habilidad '%s'" % [pid, str(want)])
			elif seen.has(str(want)):
				errs.append("character.json: habilidad '%s' duplicada (ya viene de: %s)" % [str(want), seen[str(want)]])
			else:
				seen[str(want)] = pid
				abilities.append((found as Dictionary).duplicate(true))
	data["abilities"] = abilities
	if not scripts.is_empty():
		data["scripts"] = scripts.duplicate()
	if parsed.has("effects.json"):
		data["statuses"] = (parsed["effects.json"]["statuses"] as Array).duplicate(true)
	if parsed.has("summons.json"):
		data["summons"] = (parsed["summons.json"]["summons"] as Dictionary).duplicate(true)
	if parsed.has("artifact.json"):
		var art: Dictionary = (parsed["artifact.json"] as Dictionary).duplicate(true)
		art.erase("schema")
		data["artifact"] = art

	var has_inline: bool = parsed.has("ai.json") and parsed["ai.json"].has("ai")
	if has_inline and ch.has("ai_ref"):
		errs.append("character.json: 'ai_ref' y ai.json/'ai' a la vez; use solo uno")
	elif has_inline:
		data["ai"] = parsed["ai.json"]["ai"].duplicate(true)
	elif ch.has("ai_ref"):
		var r: Dictionary = ch["ai_ref"]
		var pid2 := str(r["package"])
		used[pid2] = true
		if not declared.has(pid2):
			errs.append("character.json: ai_ref usa '%s', que no esta declarada en manifest.dependencies" % pid2)
		elif resolved[pid2]["manifest"].get("type", "") != "ai":
			errs.append("character.json: ai_ref: '%s' no es un paquete de IA" % pid2)
		else:
			var strategies: Dictionary = resolved[pid2]["parsed"]["ai.json"].get("strategies", {})
			if not strategies.has(str(r["strategy"])):
				errs.append("character.json: el paquete '%s' no define la estrategia '%s'" % [pid2, str(r["strategy"])])
			else:
				data["ai"] = (strategies[str(r["strategy"])] as Dictionary).duplicate(true)

	var dep_ids: Array = declared.keys()
	dep_ids.sort() # orden determinista, independiente del manifiesto
	for dep_id in dep_ids:
		if not used.has(dep_id):
			warns.append("manifest.json: la dependencia '%s' se declara pero no se usa" % dep_id)
		if resolved.has(dep_id):
			deps.append({"id": dep_id, "version": resolved[dep_id]["manifest"]["version"], "hash": resolved[dep_id]["hash"]})
	return {"data": data, "errors": errs, "warnings": warns, "deps": deps}
