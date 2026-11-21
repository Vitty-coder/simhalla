class_name ScriptCompiler
extends RefCounted
## Compilador de SimScript v1: texto -> AST (ScriptProgram). Nunca ejecuta nada.
##
## SimScript es un lenguaje minimo propio, sin acceso al anfitrion:
##   // comentario
##   const BASE = 40;
##   fn helper(a, b) { return a * b + BASE; }
##   fn run(ctx) {                       // punto de entrada de un efecto
##     let total = 0;
##     for t in ctx.targets { total = total + hp(t); }
##     while total > 100 { total = total - 50; }   // acotado por el presupuesto de instrucciones
##     if total > 10 and not alive(ctx.caster) { return null; } else if ... { } else { }
##     deal_damage(ctx.targets[0], total * 0.5, {"damage_type": "magical", "element": "fire"});
##   }
## Tipos: numero (float), texto, booleano, null, lista, mapa. Las condiciones exigen booleanos.
## Solo se pueden llamar funciones propias y las del catalogo ScriptApi (lista permitida).
## No hay import, eval, reflexion, acceso a objetos, E/S ni funciones como valores.

const KEYWORDS := ["fn", "let", "const", "if", "else", "while", "for", "in", "return", "break", "continue", "true", "false", "null", "and", "or", "not"]
const MAX_PARSE_DEPTH := 32
const MAX_NAME := 64

var _limits: ScriptLimits
var _toks: Array = []
var _p: int = 0
var _errs: Array = []
var _nodes: int = 0
var _depth: int = 0
var _file: String = ""
var _consts: Dictionary = {}
var _fns: Dictionary = {}


## Devuelve {"program": ScriptProgram|null, "errors": Array[String]}.
static func compile(source: String, script_name: String, limits: ScriptLimits = null) -> Dictionary:
	var c := ScriptCompiler.new()
	c._limits = limits if limits != null else ScriptLimits.default_limits()
	c._file = script_name
	return c._run(source)


func _err(line: int, msg: String) -> void:
	if _errs.size() < 20:
		_errs.append("%s:%d: %s" % [_file, line, msg])


func _run(source: String) -> Dictionary:
	var bytes := source.to_utf8_buffer()
	if bytes.size() > _limits.max_source_bytes:
		return {"program": null, "errors": ["%s: [tamano] el script supera %d bytes" % [_file, _limits.max_source_bytes]]}
	if bytes.has(0):
		return {"program": null, "errors": ["%s: [codificacion] el script contiene NUL" % _file]}
	if not _lex(source):
		return {"program": null, "errors": _errs}
	var prog := ScriptProgram.new()
	prog.name = _file
	prog.source_size = bytes.size()
	var h := HashingContext.new()
	h.start(HashingContext.HASH_SHA256)
	h.update(bytes)
	prog.source_hash = h.finish().hex_encode()
	_parse_top(prog)
	if _errs.is_empty():
		_analyze(prog)
	if not _errs.is_empty():
		return {"program": null, "errors": _errs}
	return {"program": prog, "errors": []}


# --- Lexer -----------------------------------------------------------------------------------------

func _lex(src: String) -> bool:
	var i := 0
	var line := 1
	var n := src.length()
	var max_tokens := _limits.max_ast_nodes * 3
	while i < n:
		var c := src[i]
		if c == "\n":
			line += 1
			i += 1
		elif c == " " or c == "\t" or c == "\r":
			i += 1
		elif c == "/" and i + 1 < n and src[i + 1] == "/":
			while i < n and src[i] != "\n":
				i += 1
		elif c >= "0" and c <= "9":
			var j := i
			while j < n and src[j] >= "0" and src[j] <= "9":
				j += 1
			if j + 1 < n and src[j] == "." and src[j + 1] >= "0" and src[j + 1] <= "9":
				j += 1
				while j < n and src[j] >= "0" and src[j] <= "9":
					j += 1
			var text := src.substr(i, j - i)
			if text.length() > 18:
				_err(line, "numero demasiado largo")
				return false
			_toks.append(["num", text.to_float(), line])
			i = j
		elif c == "\"":
			var j2 := i + 1
			var sb := ""
			var closed := false
			while j2 < n:
				var d := src[j2]
				if d == "\"":
					closed = true
					break
				if d == "\n":
					break
				if d == "\\":
					j2 += 1
					if j2 >= n:
						break
					match src[j2]:
						"n":
							sb += "\n"
						"t":
							sb += "\t"
						"\"":
							sb += "\""
						"\\":
							sb += "\\"
						_:
							_err(line, "escape desconocido '\\%s'" % src[j2])
							return false
				else:
					sb += d
				j2 += 1
				if sb.length() > _limits.max_string:
					_err(line, "texto literal demasiado largo (max %d)" % _limits.max_string)
					return false
			if not closed:
				_err(line, "texto sin cerrar")
				return false
			_toks.append(["str", sb, line])
			i = j2 + 1
		elif (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_":
			var j3 := i
			while j3 < n and ((src[j3] >= "a" and src[j3] <= "z") or (src[j3] >= "A" and src[j3] <= "Z") or src[j3] == "_" or (src[j3] >= "0" and src[j3] <= "9")):
				j3 += 1
			var word := src.substr(i, j3 - i)
			if word.length() > MAX_NAME:
				_err(line, "identificador demasiado largo")
				return false
			_toks.append(["kw" if KEYWORDS.has(word) else "id", word, line])
			i = j3
		else:
			var two := src.substr(i, 2)
			if ["==", "!=", "<=", ">=", "&&", "||"].has(two):
				_toks.append(["op", two, line])
				i += 2
			elif "+-*/%<>=(){}[],;.:!".contains(c):
				_toks.append(["op", c, line])
				i += 1
			else:
				_err(line, "caracter no permitido '%s'" % c)
				return false
		if _toks.size() > max_tokens:
			_err(line, "script demasiado grande (tokens)")
			return false
	_toks.append(["eof", "", line])
	return true


# --- Parser ----------------------------------------------------------------------------------------

func _peek() -> Array:
	return _toks[_p]


func _is(type: String, value: Variant = null) -> bool:
	var t: Array = _toks[_p]
	return t[0] == type and (value == null or t[1] == value)


func _is_op(v: String) -> bool:
	return _is("op", v)


func _line() -> int:
	return int((_toks[_p] as Array)[2])


func _accept(type: String, value: Variant = null) -> bool:
	if _is(type, value):
		_p += 1
		return true
	return false


func _expect(type: String, value: Variant, what: String) -> bool:
	if _accept(type, value):
		return true
	var t: Array = _toks[_p]
	_err(int(t[2]), "se esperaba %s" % what)
	return false


func _node() -> bool:
	_nodes += 1
	if _nodes > _limits.max_ast_nodes:
		if _nodes == _limits.max_ast_nodes + 1:
			_err(_line(), "script demasiado grande (maximo %d nodos)" % _limits.max_ast_nodes)
		return false
	return true


func _ok() -> bool:
	return _errs.is_empty()


func _parse_top(prog: ScriptProgram) -> void:
	while not _is("eof") and _ok():
		var line := _line()
		if _accept("kw", "const"):
			if not _is("id"):
				_err(line, "se esperaba el nombre de la constante")
				return
			var cname: String = str(_peek()[1])
			_p += 1
			_check_new_name(cname, line, true)
			if not _expect("op", "=", "'='"):
				return
			var neg := _accept("op", "-")
			var t: Array = _peek()
			var val: Variant = null
			if t[0] == "num":
				val = -float(t[1]) if neg else float(t[1])
			elif t[0] == "str" and not neg:
				val = str(t[1])
			elif t[0] == "kw" and ["true", "false", "null"].has(t[1]) and not neg:
				val = (t[1] == "true") if t[1] != "null" else null
			else:
				_err(line, "una constante solo admite un literal (numero, texto, booleano o null)")
				return
			_p += 1
			if not _is_op(";"):
				_err(line, "una constante solo admite un literal (numero, texto, booleano o null)")
				return
			_p += 1
			_consts[cname] = val
			prog.consts[cname] = val
		elif _accept("kw", "fn"):
			if not _is("id"):
				_err(line, "se esperaba el nombre de la funcion")
				return
			var fname: String = str(_peek()[1])
			_p += 1
			_check_new_name(fname, line, false)
			if not _expect("op", "(", "'('"):
				return
			var params: Array = []
			while not _is_op(")") and _ok():
				if not _is("id"):
					_err(_line(), "se esperaba un nombre de parametro")
					return
				var pn: String = str(_peek()[1])
				if params.has(pn) or ScriptApi.RESERVED.has(pn) or ScriptApi.has_function(pn):
					_err(_line(), "parametro invalido o repetido '%s'" % pn)
				params.append(pn)
				_p += 1
				if not _accept("op", ","):
					break
			if params.size() > 8:
				_err(line, "maximo 8 parametros")
			if not _expect("op", ")", "')'"):
				return
			_fns[fname] = params.size() # registrado antes del cuerpo: permite recursion
			var body := _parse_block()
			prog.functions[fname] = {"params": params, "body": body, "line": line, "calls": [], "user_calls": []}
		else:
			_err(line, "solo se admiten `fn` y `const` en el nivel superior")
			return


func _check_new_name(nm: String, line: int, is_const: bool) -> void:
	if ScriptApi.RESERVED.has(nm) or KEYWORDS.has(nm):
		_err(line, "'%s' es una palabra reservada" % nm)
	elif ScriptApi.has_function(nm):
		_err(line, "'%s' es una funcion de la API y no puede redefinirse" % nm)
	elif _fns.has(nm) or _consts.has(nm):
		_err(line, "'%s' ya esta definido" % nm)


func _parse_block() -> Array:
	var stmts: Array = []
	if not _expect("op", "{", "'{'"):
		return stmts
	_depth += 1
	if _depth > MAX_PARSE_DEPTH:
		_err(_line(), "anidamiento demasiado profundo")
		return stmts
	while not _is_op("}") and not _is("eof") and _ok():
		var s: Variant = _parse_stmt()
		if s != null:
			stmts.append(s)
	_expect("op", "}", "'}'")
	_depth -= 1
	return stmts


func _parse_stmt() -> Variant:
	if not _node():
		return null
	var line := _line()
	if _accept("kw", "let"):
		if not _is("id"):
			_err(line, "se esperaba un nombre de variable")
			return null
		var nm: String = str(_peek()[1])
		_p += 1
		if ScriptApi.RESERVED.has(nm) or ScriptApi.has_function(nm) or _fns.has(nm) or _consts.has(nm):
			_err(line, "nombre de variable no permitido '%s'" % nm)
		if not _expect("op", "=", "'='"):
			return null
		var e: Variant = _parse_expr()
		_expect("op", ";", "';'")
		return ["let", line, nm, e]
	if _accept("kw", "if"):
		var branches: Array = []
		var cond: Variant = _parse_expr()
		branches.append([cond, _parse_block()])
		var else_b: Variant = null
		while _accept("kw", "else"):
			if _accept("kw", "if"):
				var c2: Variant = _parse_expr()
				branches.append([c2, _parse_block()])
			else:
				else_b = _parse_block()
				break
		return ["if", line, branches, else_b]
	if _accept("kw", "while"):
		var wc: Variant = _parse_expr()
		return ["while", line, wc, _parse_block()]
	if _accept("kw", "for"):
		if not _is("id"):
			_err(line, "se esperaba el nombre de la variable del bucle")
			return null
		var vn: String = str(_peek()[1])
		_p += 1
		if ScriptApi.RESERVED.has(vn) or ScriptApi.has_function(vn):
			_err(line, "nombre de variable no permitido '%s'" % vn)
		if not _expect("kw", "in", "'in'"):
			return null
		var it: Variant
		if _is("id", "range") and _toks[_p + 1][1] == "(":
			_p += 2
			var rargs: Array = []
			while not _is_op(")") and _ok():
				rargs.append(_parse_expr())
				if not _accept("op", ","):
					break
			_expect("op", ")", "')'")
			if rargs.size() < 1 or rargs.size() > 2:
				_err(line, "range admite 1 o 2 argumentos")
			it = ["range", line, rargs]
		else:
			it = _parse_expr()
		return ["for", line, vn, it, _parse_block()]
	if _accept("kw", "return"):
		var rv: Variant = null
		if not _is_op(";"):
			rv = _parse_expr()
		_expect("op", ";", "';'")
		return ["return", line, rv]
	if _accept("kw", "break"):
		_expect("op", ";", "';'")
		return ["break", line]
	if _accept("kw", "continue"):
		_expect("op", ";", "';'")
		return ["continue", line]
	if _is_op("{"):
		_err(line, "un bloque suelto no es una sentencia valida")
		return null
	var ex: Variant = _parse_expr()
	if _accept("op", "="):
		if not (ex is Array) or not ["var", "index", "member"].has((ex as Array)[0]):
			_err(line, "solo se puede asignar a una variable, un indice o un miembro")
		var rhs: Variant = _parse_expr()
		_expect("op", ";", "';'")
		return ["assign", line, ex, rhs]
	_expect("op", ";", "';'")
	if not (ex is Array) or (ex as Array)[0] != "call":
		_err(line, "una sentencia de expresion debe ser una llamada")
	return ["expr", line, ex]


func _enter() -> bool:
	_depth += 1
	if _depth > MAX_PARSE_DEPTH:
		if _errs.is_empty():
			_err(_line(), "expresion demasiado anidada")
		return false
	return true


func _parse_expr() -> Variant:
	if not _ok() or not _enter():
		_depth -= 1
		return null
	var r: Variant = _parse_or()
	_depth -= 1
	return r


func _parse_or() -> Variant:
	var a: Variant = _parse_and()
	while (_is("kw", "or") or _is_op("||")) and _ok():
		var line := _line()
		_p += 1
		_node()
		a = ["or", line, a, _parse_and()]
	return a


func _parse_and() -> Variant:
	var a: Variant = _parse_cmp()
	while (_is("kw", "and") or _is_op("&&")) and _ok():
		var line := _line()
		_p += 1
		_node()
		a = ["and", line, a, _parse_cmp()]
	return a


func _parse_cmp() -> Variant:
	var a: Variant = _parse_add()
	var t: Array = _peek()
	if t[0] == "op" and ["==", "!=", "<", "<=", ">", ">="].has(t[1]) and _ok():
		_p += 1
		_node()
		return ["bin", int(t[2]), str(t[1]), a, _parse_add()]
	return a


func _parse_add() -> Variant:
	var a: Variant = _parse_mul()
	while (_is_op("+") or _is_op("-")) and _ok():
		var t: Array = _peek()
		_p += 1
		_node()
		a = ["bin", int(t[2]), str(t[1]), a, _parse_mul()]
	return a


func _parse_mul() -> Variant:
	var a: Variant = _parse_unary()
	while (_is_op("*") or _is_op("/") or _is_op("%")) and _ok():
		var t: Array = _peek()
		_p += 1
		_node()
		a = ["bin", int(t[2]), str(t[1]), a, _parse_unary()]
	return a


func _parse_unary() -> Variant:
	var line := _line()
	if _is_op("-") or _is("kw", "not") or _is_op("!"):
		var op: String = "-" if _is_op("-") else "not"
		_p += 1
		_node()
		if not _enter():
			_depth -= 1
			return null
		var e: Variant = _parse_unary()
		_depth -= 1
		return ["un", line, op, e]
	return _parse_postfix()


func _parse_postfix() -> Variant:
	var a: Variant = _parse_primary()
	while _ok():
		var line := _line()
		if _accept("op", "["):
			_node()
			var idx: Variant = _parse_expr()
			_expect("op", "]", "']'")
			a = ["index", line, a, idx]
		elif _accept("op", "."):
			_node()
			if not _is("id") and not _is("kw"):
				_err(line, "se esperaba un nombre tras '.'")
				return a
			a = ["member", line, a, str(_peek()[1])]
			_p += 1
			if _is_op("("):
				_err(line, "SimScript no tiene llamadas a metodos (`x.f()`): use las funciones de la API")
				return a
		else:
			break
	return a


func _parse_primary() -> Variant:
	if not _ok() or not _node():
		return null
	var t: Array = _peek()
	var line := int(t[2])
	match t[0]:
		"num":
			_p += 1
			return ["num", line, t[1]]
		"str":
			_p += 1
			return ["str", line, t[1]]
		"kw":
			if t[1] == "true" or t[1] == "false":
				_p += 1
				return ["bool", line, t[1] == "true"]
			if t[1] == "null":
				_p += 1
				return ["null", line]
		"id":
			_p += 1
			if _is_op("("):
				_p += 1
				var args: Array = []
				while not _is_op(")") and _ok():
					args.append(_parse_expr())
					if not _accept("op", ","):
						break
				_expect("op", ")", "')'")
				if args.size() > 8:
					_err(line, "maximo 8 argumentos")
				return ["call", line, str(t[1]), args]
			return ["var", line, str(t[1])]
		"op":
			if t[1] == "(":
				_p += 1
				var e: Variant = _parse_expr()
				_expect("op", ")", "')'")
				return e
			if t[1] == "[":
				_p += 1
				var items: Array = []
				while not _is_op("]") and _ok():
					items.append(_parse_expr())
					if not _accept("op", ","):
						break
				_expect("op", "]", "']'")
				if items.size() > _limits.max_collection:
					_err(line, "lista literal demasiado grande (max %d)" % _limits.max_collection)
				return ["list", line, items]
			if t[1] == "{":
				_p += 1
				var pairs: Array = []
				while not _is_op("}") and _ok():
					var kt: Array = _peek()
					if kt[0] != "id" and kt[0] != "str" and kt[0] != "kw":
						_err(line, "clave de mapa invalida (use un nombre o un texto)")
						return null
					_p += 1
					if not _expect("op", ":", "':'"):
						return null
					pairs.append([str(kt[1]), _parse_expr()])
					if not _accept("op", ","):
						break
				_expect("op", "}", "'}'")
				if pairs.size() > _limits.max_collection:
					_err(line, "mapa literal demasiado grande (max %d)" % _limits.max_collection)
				return ["map", line, pairs]
	_err(line, "expresion inesperada '%s'" % str(t[1]))
	_p += 1
	return null


# --- Analisis estatico -------------------------------------------------------------------------------

func _analyze(prog: ScriptProgram) -> void:
	var info := {"mutates": false, "rng": false, "loops": false, "state": false}
	for fname in prog.functions:
		var f: Dictionary = prog.functions[fname]
		var scopes: Array = [{}]
		for pn in f["params"]:
			scopes[0][pn] = true
		var calls := {}
		var ucalls := {}
		_check_block(f["body"], scopes, 0, calls, ucalls, info, prog)
		var cl: Array = calls.keys()
		cl.sort()
		var ul: Array = ucalls.keys()
		ul.sort()
		f["calls"] = cl
		f["user_calls"] = ul
	var all: Dictionary = {}
	for fname in prog.functions:
		for c in prog.functions[fname]["calls"]:
			all[c] = true
	var names: Array = all.keys()
	names.sort()
	prog.analysis = {
		"api_version": ScriptApi.VERSION, "calls": names, "functions": prog.functions.keys(),
		"mutates": info["mutates"], "uses_rng": info["rng"], "has_loops": info["loops"], "uses_state": info["state"],
		"nodes": _nodes, "source_hash": prog.source_hash,
	}


func _declared(scopes: Array, nm: String, prog: ScriptProgram) -> bool:
	if prog.consts.has(nm):
		return true
	for s in scopes:
		if (s as Dictionary).has(nm):
			return true
	return false


func _check_block(block: Array, scopes: Array, loop: int, calls: Dictionary, ucalls: Dictionary, info: Dictionary, prog: ScriptProgram) -> void:
	scopes.append({})
	for s in block:
		_check_stmt(s, scopes, loop, calls, ucalls, info, prog)
	scopes.pop_back()


func _check_stmt(s: Array, scopes: Array, loop: int, calls: Dictionary, ucalls: Dictionary, info: Dictionary, prog: ScriptProgram) -> void:
	var line := int(s[1])
	match s[0]:
		"let":
			_check_expr(s[3], scopes, calls, ucalls, info, prog)
			(scopes[scopes.size() - 1] as Dictionary)[s[2]] = true
		"assign":
			var tgt: Array = s[2]
			if tgt[0] == "var" and prog.consts.has(tgt[2]):
				_err(line, "no se puede asignar a la constante '%s'" % str(tgt[2]))
			_check_expr(tgt, scopes, calls, ucalls, info, prog)
			_check_expr(s[3], scopes, calls, ucalls, info, prog)
		"if":
			for br in s[2]:
				_check_expr(br[0], scopes, calls, ucalls, info, prog)
				_check_block(br[1], scopes, loop, calls, ucalls, info, prog)
			if s[3] != null:
				_check_block(s[3], scopes, loop, calls, ucalls, info, prog)
		"while":
			info["loops"] = true
			_check_expr(s[2], scopes, calls, ucalls, info, prog)
			_check_block(s[3], scopes, loop + 1, calls, ucalls, info, prog)
		"for":
			info["loops"] = true
			var it: Array = s[3]
			if it[0] == "range":
				for a in it[2]:
					_check_expr(a, scopes, calls, ucalls, info, prog)
			else:
				_check_expr(it, scopes, calls, ucalls, info, prog)
			scopes.append({s[2]: true})
			_check_block(s[4], scopes, loop + 1, calls, ucalls, info, prog)
			scopes.pop_back()
		"return":
			if s[2] != null:
				_check_expr(s[2], scopes, calls, ucalls, info, prog)
		"break", "continue":
			if loop == 0:
				_err(line, "`%s` fuera de un bucle" % str(s[0]))
		"expr":
			_check_expr(s[2], scopes, calls, ucalls, info, prog)


func _check_expr(e: Variant, scopes: Array, calls: Dictionary, ucalls: Dictionary, info: Dictionary, prog: ScriptProgram) -> void:
	if not (e is Array):
		return
	var ex: Array = e
	var line := int(ex[1])
	match ex[0]:
		"var":
			if not _declared(scopes, str(ex[2]), prog):
				_err(line, "variable no declarada '%s'" % str(ex[2]))
		"list":
			for x in ex[2]:
				_check_expr(x, scopes, calls, ucalls, info, prog)
		"map":
			for pr in ex[2]:
				_check_expr(pr[1], scopes, calls, ucalls, info, prog)
		"un":
			_check_expr(ex[3], scopes, calls, ucalls, info, prog)
		"bin", "and", "or":
			_check_expr(ex[ex.size() - 2], scopes, calls, ucalls, info, prog)
			_check_expr(ex[ex.size() - 1], scopes, calls, ucalls, info, prog)
		"index":
			_check_expr(ex[2], scopes, calls, ucalls, info, prog)
			_check_expr(ex[3], scopes, calls, ucalls, info, prog)
		"member":
			_check_expr(ex[2], scopes, calls, ucalls, info, prog)
		"call":
			var nm := str(ex[2])
			var argc: int = (ex[3] as Array).size()
			if _fns.has(nm):
				if argc != int(_fns[nm]):
					_err(line, "`%s` espera %d argumento(s), recibe %d" % [nm, int(_fns[nm]), argc])
				ucalls[nm] = true
			elif ScriptApi.has_function(nm):
				var ar: Array = ScriptApi.arity(nm)
				if argc < int(ar[0]) or argc > int(ar[1]):
					_err(line, "`%s` espera %s argumento(s), recibe %d" % [nm, (str(ar[0]) if ar[0] == ar[1] else "%d-%d" % [ar[0], ar[1]]), argc])
				calls[nm] = true
				match ScriptApi.kind_of(nm):
					"mutate":
						info["mutates"] = true
					"rng":
						info["rng"] = true
					"state":
						info["state"] = true
						if nm == "set_var":
							info["mutates"] = true
			else:
				_err(line, "funcion no permitida o desconocida `%s` (API v%d)" % [nm, ScriptApi.VERSION])
			for a in ex[3]:
				_check_expr(a, scopes, calls, ucalls, info, prog)
