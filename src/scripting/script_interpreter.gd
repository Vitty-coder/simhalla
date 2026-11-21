class_name ScriptInterpreter
extends RefCounted
## Interprete de SimScript: recorre el AST con un presupuesto de instrucciones.
##
## Aislamiento: el unico canal con el exterior es `host.call_api(nombre, args)`, que solo recibe
## nombres del catalogo ScriptApi permitidos en el contexto. Los valores son datos puros
## (float, String, bool, null, Array, Dictionary): el script nunca ve objetos del motor/Godot.
## Limites (ScriptLimits): instrucciones, profundidad de llamadas, tamano de colecciones y
## textos. Todo error es controlado: se devuelve {"ok": false, "error": ...} sin tocar el host.
## Determinista: sin reloj ni azar propio (el RNG solo existe via el host, flujo del motor).
## Semantica: las colecciones se COPIAN al guardarlas dentro de otras o al asignarlas por
## indice/miembro (imposible crear ciclos); `let a = b` comparte referencia.

const SIG_NONE := 0
const SIG_BREAK := 1
const SIG_CONTINUE := 2
const SIG_RETURN := 3

var program: ScriptProgram
var limits: ScriptLimits
var host: Object = null ## con call_api(name: String, args: Array) -> Dictionary {ok, value, error}
var context: String = ""
var instructions: int = 0
var api_calls: int = 0
var _err: String = ""
var _ret: Variant = null
var _depth: int = 0


func _init(prog: ScriptProgram, lim: ScriptLimits, host_: Object, ctx_kind: String) -> void:
	program = prog
	limits = lim
	host = host_
	context = ctx_kind


## Ejecuta `fn_name(args)`. Devuelve {"ok", "value", "error", "instructions"}.
func call_entry(fn_name: String, args: Array) -> Dictionary:
	instructions = 0
	_err = ""
	var v: Variant = _call_user(fn_name, args, 0)
	if _err != "":
		return {"ok": false, "value": null, "error": _err, "instructions": instructions}
	return {"ok": true, "value": v, "error": "", "instructions": instructions}


func _fail(line: int, msg: String) -> Variant:
	if _err == "":
		_err = "%s:%d: %s" % [program.name, line, msg]
	return null


func _tick(line: int, cost: int = 1) -> bool:
	instructions += cost
	if instructions > limits.max_instructions:
		_fail(line, "[limite] se supero el presupuesto de %d instrucciones" % limits.max_instructions)
		return false
	return true


# --- Llamadas ----------------------------------------------------------------------------------------

func _call_user(fn_name: String, args: Array, line: int) -> Variant:
	if not program.functions.has(fn_name):
		return _fail(line, "funcion inexistente '%s'" % fn_name)
	var f: Dictionary = program.functions[fn_name]
	if (f["params"] as Array).size() != args.size():
		return _fail(line, "`%s` espera %d argumento(s)" % [fn_name, (f["params"] as Array).size()])
	if _depth >= limits.max_call_depth:
		return _fail(line, "[limite] profundidad de llamadas maxima (%d)" % limits.max_call_depth)
	_depth += 1
	var scope := {}
	for i in args.size():
		scope[f["params"][i]] = args[i]
	var env: Array = [scope]
	var sig := _exec_block(f["body"], env)
	_depth -= 1
	if _err != "":
		return null
	if sig == SIG_RETURN:
		var r: Variant = _ret
		_ret = null
		return r
	return null


func _exec_block(block: Array, env: Array) -> int:
	env.append({})
	var sig := SIG_NONE
	for s in block:
		sig = _exec(s, env)
		if sig != SIG_NONE or _err != "":
			break
	env.pop_back()
	return sig


func _exec(s: Array, env: Array) -> int:
	var line := int(s[1])
	if not _tick(line):
		return SIG_NONE
	match s[0]:
		"let":
			var v: Variant = _eval(s[3], env)
			if _err != "":
				return SIG_NONE
			(env[env.size() - 1] as Dictionary)[s[2]] = v
		"assign":
			var rv: Variant = _eval(s[3], env)
			if _err != "":
				return SIG_NONE
			_assign(s[2], rv, env, line)
		"if":
			for br in s[2]:
				var c: Variant = _eval(br[0], env)
				if _err != "":
					return SIG_NONE
				if not (c is bool):
					_fail(line, "la condicion debe ser booleana (es %s)" % _type_name(c))
					return SIG_NONE
				if c:
					return _exec_block(br[1], env)
			if s[3] != null:
				return _exec_block(s[3], env)
		"while":
			while true:
				var c2: Variant = _eval(s[2], env)
				if _err != "":
					return SIG_NONE
				if not (c2 is bool):
					_fail(line, "la condicion debe ser booleana (es %s)" % _type_name(c2))
					return SIG_NONE
				if not c2:
					break
				var sg := _exec_block(s[3], env)
				if _err != "":
					return SIG_NONE
				if sg == SIG_BREAK:
					break
				if sg == SIG_RETURN:
					return sg
				if not _tick(line):
					return SIG_NONE
		"for":
			return _exec_for(s, env)
		"return":
			_ret = null
			if s[2] != null:
				var rr: Variant = _eval(s[2], env)
				if _err != "":
					return SIG_NONE
				_ret = rr
			return SIG_RETURN
		"break":
			return SIG_BREAK
		"continue":
			return SIG_CONTINUE
		"expr":
			_eval(s[2], env)
	return SIG_NONE


func _exec_for(s: Array, env: Array) -> int:
	var line := int(s[1])
	var items: Array = []
	var it: Array = s[3]
	if it[0] == "range":
		var a: Variant = _eval(it[2][0], env)
		if _err != "":
			return SIG_NONE
		var lo := 0.0
		var hi := 0.0
		if (it[2] as Array).size() == 1:
			hi = _num_arg(a, line)
		else:
			var b: Variant = _eval(it[2][1], env)
			if _err != "":
				return SIG_NONE
			lo = _num_arg(a, line)
			hi = _num_arg(b, line)
		if _err != "":
			return SIG_NONE
		var i := int(floorf(lo))
		var end := int(floorf(hi))
		if end - i > limits.max_instructions:
			_fail(line, "[limite] el rango excede el presupuesto de instrucciones")
			return SIG_NONE
		while i < end:
			items.append(float(i))
			i += 1
	else:
		var coll: Variant = _eval(it, env)
		if _err != "":
			return SIG_NONE
		if not (coll is Array):
			_fail(line, "`for` recorre una lista o range(), no %s" % _type_name(coll))
			return SIG_NONE
		items = (coll as Array).duplicate()
	for item in items:
		if not _tick(line):
			return SIG_NONE
		env.append({s[2]: item})
		var sg := _exec_block(s[4], env)
		env.pop_back()
		if _err != "":
			return SIG_NONE
		if sg == SIG_BREAK:
			break
		if sg == SIG_RETURN:
			return sg
	return SIG_NONE


func _lookup(env: Array, nm: String) -> Variant:
	for i in range(env.size() - 1, -1, -1):
		if (env[i] as Dictionary).has(nm):
			return (env[i] as Dictionary)[nm]
	if program.consts.has(nm):
		return program.consts[nm]
	return null


func _assign(tgt: Array, value: Variant, env: Array, line: int) -> void:
	match tgt[0]:
		"var":
			for i in range(env.size() - 1, -1, -1):
				if (env[i] as Dictionary).has(tgt[2]):
					(env[i] as Dictionary)[tgt[2]] = value
					return
			_fail(line, "variable no declarada '%s'" % str(tgt[2]))
		"index":
			var coll: Variant = _eval(tgt[2], env)
			var idx: Variant = _eval(tgt[3], env)
			if _err != "":
				return
			var stored: Variant = _store_copy(value, line)
			if _err != "":
				return
			if coll is Array:
				var i := _index_of(idx, (coll as Array).size(), line)
				if _err == "":
					(coll as Array)[i] = stored
			elif coll is Dictionary:
				if not (idx is String):
					_fail(line, "la clave de un mapa debe ser texto")
				elif not (coll as Dictionary).has(idx) and (coll as Dictionary).size() >= limits.max_collection:
					_fail(line, "[limite] mapa demasiado grande (max %d)" % limits.max_collection)
				else:
					(coll as Dictionary)[idx] = stored
			else:
				_fail(line, "no se puede indexar %s" % _type_name(coll))
		"member":
			var m: Variant = _eval(tgt[2], env)
			if _err != "":
				return
			if not (m is Dictionary):
				_fail(line, "no se puede asignar un miembro de %s" % _type_name(m))
				return
			var st: Variant = _store_copy(value, line)
			if _err != "":
				return
			if not (m as Dictionary).has(tgt[3]) and (m as Dictionary).size() >= limits.max_collection:
				_fail(line, "[limite] mapa demasiado grande (max %d)" % limits.max_collection)
				return
			(m as Dictionary)[tgt[3]] = st


## Copia profunda de una coleccion al guardarla en otra; cobra su tamano.
func _store_copy(v: Variant, line: int) -> Variant:
	if v is Array or v is Dictionary:
		var size := _size_of(v)
		if not _tick(line, size):
			return null
		return (v as Variant).duplicate(true)
	return v


func _size_of(v: Variant) -> int:
	var n := 1
	if v is Array:
		for x in v:
			n += _size_of(x)
	elif v is Dictionary:
		for k in v:
			n += _size_of(v[k])
	return n


func _index_of(idx: Variant, size: int, line: int) -> int:
	if not (idx is float) or floorf(idx) != idx:
		_fail(line, "el indice debe ser un entero")
		return 0
	var i := int(idx)
	if i < 0 or i >= size:
		_fail(line, "indice fuera de rango (%d, tamano %d)" % [i, size])
		return 0
	return i


# --- Expresiones --------------------------------------------------------------------------------------

func _eval(e: Variant, env: Array) -> Variant:
	if _err != "" or not (e is Array):
		return null
	var ex: Array = e
	var line := int(ex[1])
	if not _tick(line):
		return null
	match ex[0]:
		"num", "str", "bool":
			return ex[2]
		"null":
			return null
		"var":
			return _lookup(env, str(ex[2]))
		"list":
			var out: Array = []
			for x in ex[2]:
				var v: Variant = _eval(x, env)
				if _err != "":
					return null
				out.append(_store_copy(v, line))
			return out
		"map":
			var m := {}
			for pr in ex[2]:
				var mv: Variant = _eval(pr[1], env)
				if _err != "":
					return null
				m[pr[0]] = _store_copy(mv, line)
			return m
		"un":
			var a: Variant = _eval(ex[3], env)
			if _err != "":
				return null
			if ex[2] == "-":
				if not (a is float):
					return _fail(line, "'-' requiere un numero (es %s)" % _type_name(a))
				return -a
			if not (a is bool):
				return _fail(line, "'not' requiere un booleano (es %s)" % _type_name(a))
			return not a
		"and", "or":
			var l: Variant = _eval(ex[2], env)
			if _err != "":
				return null
			if not (l is bool):
				return _fail(line, "'%s' requiere booleanos (es %s)" % [ex[0], _type_name(l)])
			if ex[0] == "and" and not l:
				return false
			if ex[0] == "or" and l:
				return true
			var r: Variant = _eval(ex[3], env)
			if _err != "":
				return null
			if not (r is bool):
				return _fail(line, "'%s' requiere booleanos (es %s)" % [ex[0], _type_name(r)])
			return r
		"bin":
			var x1: Variant = _eval(ex[3], env)
			if _err != "":
				return null
			var x2: Variant = _eval(ex[4], env)
			if _err != "":
				return null
			return _binary(str(ex[2]), x1, x2, line)
		"index":
			var coll: Variant = _eval(ex[2], env)
			var idx: Variant = _eval(ex[3], env)
			if _err != "":
				return null
			if coll is Array:
				var i := _index_of(idx, (coll as Array).size(), line)
				return null if _err != "" else (coll as Array)[i]
			if coll is Dictionary:
				if not (idx is String):
					return _fail(line, "la clave de un mapa debe ser texto")
				return (coll as Dictionary).get(idx, null)
			return _fail(line, "no se puede indexar %s" % _type_name(coll))
		"member":
			var mm: Variant = _eval(ex[2], env)
			if _err != "":
				return null
			if mm is Dictionary:
				return (mm as Dictionary).get(ex[3], null)
			return _fail(line, "'.%s' sobre %s: solo los mapas tienen miembros" % [str(ex[3]), _type_name(mm)])
		"call":
			return _call(ex, env)
	return _fail(line, "nodo desconocido")


func _binary(op: String, a: Variant, b: Variant, line: int) -> Variant:
	match op:
		"==":
			return typeof(a) == typeof(b) and a == b
		"!=":
			return not (typeof(a) == typeof(b) and a == b)
		"<", "<=", ">", ">=":
			if (a is float and b is float) or (a is String and b is String):
				match op:
					"<":
						return a < b
					"<=":
						return a <= b
					">":
						return a > b
				return a >= b
			return _fail(line, "'%s' compara numeros o textos del mismo tipo (%s y %s)" % [op, _type_name(a), _type_name(b)])
		"+":
			if a is float and b is float:
				return _finite(a + b, line)
			if a is String and b is String:
				if (a as String).length() + (b as String).length() > limits.max_string:
					return _fail(line, "[limite] texto demasiado largo (max %d)" % limits.max_string)
				return a + b
			if a is Array and b is Array:
				if (a as Array).size() + (b as Array).size() > limits.max_collection:
					return _fail(line, "[limite] lista demasiado grande (max %d)" % limits.max_collection)
				if not _tick(line, (a as Array).size() + (b as Array).size()):
					return null
				return (a as Array).duplicate(true) + (b as Array).duplicate(true)
			return _fail(line, "'+' no admite %s y %s" % [_type_name(a), _type_name(b)])
		"-", "*", "/", "%":
			if not (a is float and b is float):
				return _fail(line, "'%s' requiere numeros (%s y %s)" % [op, _type_name(a), _type_name(b)])
			match op:
				"-":
					return _finite(a - b, line)
				"*":
					return _finite(a * b, line)
				"/":
					if b == 0.0:
						return _fail(line, "division por cero")
					return _finite(a / b, line)
			if b == 0.0:
				return _fail(line, "modulo por cero")
			return _finite(fmod(a, b), line)
	return _fail(line, "operador desconocido '%s'" % op)


func _finite(x: float, line: int) -> Variant:
	if is_nan(x) or is_inf(x) or absf(x) > 1.0e15:
		return _fail(line, "[limite] resultado numerico fuera de rango")
	return x


func _type_name(v: Variant) -> String:
	if v == null:
		return "null"
	if v is float:
		return "numero"
	if v is String:
		return "texto"
	if v is bool:
		return "booleano"
	if v is Array:
		return "lista"
	if v is Dictionary:
		return "mapa"
	return "desconocido"


func _num_arg(v: Variant, line: int) -> float:
	if not (v is float):
		_fail(line, "se esperaba un numero (es %s)" % _type_name(v))
		return 0.0
	return v


# --- Llamadas a funciones ------------------------------------------------------------------------------

func _call(ex: Array, env: Array) -> Variant:
	var line := int(ex[1])
	var nm := str(ex[2])
	var args: Array = []
	for a in ex[3]:
		var v: Variant = _eval(a, env)
		if _err != "":
			return null
		args.append(v)
	if program.functions.has(nm):
		return _call_user(nm, args, line)
	if ScriptApi.is_pure(nm):
		return _builtin(nm, args, line)
	if not ScriptApi.allowed_in(nm, context):
		return _fail(line, "`%s()` no esta permitida en el contexto '%s'" % [nm, context])
	if host == null or not host.has_method("call_api"):
		return _fail(line, "no hay anfitrion para `%s()`" % nm)
	api_calls += 1
	var res: Dictionary = host.call_api(nm, args)
	if not _tick(line, int(res.get("cost", 0))):
		return null
	if not bool(res.get("ok", false)):
		return _fail(line, str(res.get("error", "error de la API")))
	return res.get("value", null)


func _builtin(nm: String, a: Array, line: int) -> Variant:
	match nm:
		"abs":
			return absf(_num_arg(a[0], line))
		"floor":
			return floorf(_num_arg(a[0], line))
		"ceil":
			return ceilf(_num_arg(a[0], line))
		"round":
			return roundf(_num_arg(a[0], line))
		"sqrt":
			var x := _num_arg(a[0], line)
			if x < 0.0:
				return _fail(line, "sqrt de un numero negativo")
			return sqrt(x)
		"min":
			return minf(_num_arg(a[0], line), _num_arg(a[1], line))
		"max":
			return maxf(_num_arg(a[0], line), _num_arg(a[1], line))
		"clamp":
			var lo := _num_arg(a[1], line)
			var hi := _num_arg(a[2], line)
			if lo > hi:
				return _fail(line, "clamp: minimo mayor que maximo")
			return clampf(_num_arg(a[0], line), lo, hi)
		"len":
			if a[0] is Array or a[0] is Dictionary or a[0] is String:
				return float(a[0].size() if not (a[0] is String) else (a[0] as String).length())
			return _fail(line, "len() no admite %s" % _type_name(a[0]))
		"str":
			var s := _to_text(a[0])
			if s.length() > limits.max_string:
				return _fail(line, "[limite] texto demasiado largo (max %d)" % limits.max_string)
			return s
		"num":
			if a[0] is float:
				return a[0]
			if a[0] is String and (a[0] as String).is_valid_float():
				return (a[0] as String).to_float()
			return _fail(line, "num(): no se puede convertir %s" % _type_name(a[0]))
		"type":
			return _type_name(a[0])
		"push":
			if not (a[0] is Array):
				return _fail(line, "push() requiere una lista")
			if (a[0] as Array).size() >= limits.max_collection:
				return _fail(line, "[limite] lista demasiado grande (max %d)" % limits.max_collection)
			var item: Variant = _store_copy(a[1], line)
			if _err != "":
				return null
			(a[0] as Array).append(item)
			return float((a[0] as Array).size())
		"pop":
			if not (a[0] is Array) or (a[0] as Array).is_empty():
				return _fail(line, "pop() requiere una lista no vacia")
			return (a[0] as Array).pop_back()
		"keys":
			if not (a[0] is Dictionary):
				return _fail(line, "keys() requiere un mapa")
			var ks: Array = (a[0] as Dictionary).keys()
			ks.sort()
			return ks
		"has":
			if a[0] is Dictionary:
				return a[1] is String and (a[0] as Dictionary).has(a[1])
			if a[0] is Array:
				for x in a[0]:
					if typeof(x) == typeof(a[1]) and x == a[1]:
						return true
				return false
			if a[0] is String and a[1] is String:
				return (a[0] as String).contains(a[1])
			return _fail(line, "has() no admite %s" % _type_name(a[0]))
		"sort":
			if not (a[0] is Array):
				return _fail(line, "sort() requiere una lista")
			var l: Array = (a[0] as Array).duplicate()
			if not _tick(line, l.size()):
				return null
			var all_num := true
			var all_str := true
			for x in l:
				all_num = all_num and x is float
				all_str = all_str and x is String
			if not (all_num or all_str):
				return _fail(line, "sort() requiere una lista solo de numeros o solo de textos")
			l.sort()
			return l
		"sum":
			if not (a[0] is Array):
				return _fail(line, "sum() requiere una lista")
			var total := 0.0
			for x in a[0]:
				if not (x is float):
					return _fail(line, "sum() requiere numeros")
				total += x
			return _finite(total, line)
		"concat":
			return _binary("+", a[0], a[1], line) if (a[0] is Array and a[1] is Array) else _fail(line, "concat() requiere dos listas")
	return _fail(line, "funcion pura desconocida '%s'" % nm)


func _to_text(v: Variant) -> String:
	if v == null:
		return "null"
	if v is float:
		if floorf(v) == v and absf(v) < 1.0e15:
			return str(int(v))
		var t := "%.6f" % v
		while t.ends_with("0"):
			t = t.substr(0, t.length() - 1)
		return t.trim_suffix(".")
	if v is bool:
		return "true" if v else "false"
	if v is String:
		return v
	return JSON.stringify(v, "", true)
