class_name Formula
extends RefCounted
## Expresiones aritmeticas con gramatica segura y limitada (nunca `eval`).
##
## Gramatica:
##   expr    := term (('+' | '-') term)*
##   term    := unary (('*' | '/' | '%') unary)*
##   unary   := '-' unary | power
##   power   := primary ('^' unary)?
##   primary := NUMBER | PATH | FUNC '(' [expr (',' expr)*] ')' | '(' expr ')'
##   PATH    := IDENT ('.' IDENT)*        p. ej. caster.ATK, target.ELEM_RES.fire
##   FUNC    := min | max | clamp | abs | floor | ceil | round | sqrt
##
## Los PATH se resuelven mediante un Callable(parts: Array) -> Dictionary
## {"ok": bool, "value": float, "error": String} suministrado por el motor, de
## modo que la formula solo ve los datos que el motor decida exponer.
## Limites duros: longitud, numero de nodos y profundidad.

const MAX_LENGTH := 512
const MAX_NODES := 256
const MAX_DEPTH := 32
const FUNCS := {"min": -1, "max": -1, "clamp": 3, "abs": 1, "floor": 1, "ceil": 1, "round": 1, "sqrt": 1}

var source: String = ""
var error: String = ""
var _ast: Array = []
var _tokens: Array = []
var _pos: int = 0
var _nodes: int = 0


static func parse(text: String) -> Formula:
	var f := Formula.new()
	f.source = text
	f._parse_all()
	return f


func is_valid() -> bool:
	return error == ""


## Evalua con el resolvedor de rutas dado. Devuelve {"ok","value","error"}.
func evaluate(resolver: Callable) -> Dictionary:
	if error != "":
		return {"ok": false, "value": 0.0, "error": error}
	var res := _eval(_ast, resolver, 0)
	return res


## Rutas (como texto "caster.ATK") usadas por la formula; util para validar.
func referenced_paths() -> Array:
	var out: Array = []
	if error == "":
		_collect(_ast, out)
	return out


# --- Parser -----------------------------------------------------------------

func _parse_all() -> void:
	if source.length() > MAX_LENGTH:
		error = "formula demasiado larga (max %d caracteres)" % MAX_LENGTH
		return
	if source.strip_edges() == "":
		error = "formula vacia"
		return
	if not _tokenize():
		return
	_pos = 0
	var node: Variant = _parse_expr(0)
	if error != "":
		return
	if _pos < _tokens.size():
		error = "token inesperado '%s'" % str(_tokens[_pos][1])
		return
	_ast = node


func _tokenize() -> bool:
	var i := 0
	var n := source.length()
	while i < n:
		var c := source[i]
		if c == " " or c == "\t" or c == "\n" or c == "\r":
			i += 1
		elif _is_digit(c) or (c == "." and i + 1 < n and _is_digit(source[i + 1])):
			var j := i
			var dots := 0
			while j < n and (_is_digit(source[j]) or source[j] == "."):
				if source[j] == ".":
					dots += 1
				j += 1
			if dots > 1:
				error = "numero mal formado '%s'" % source.substr(i, j - i)
				return false
			_tokens.append(["num", source.substr(i, j - i).to_float()])
			i = j
		elif _is_ident_start(c):
			var j := i
			while j < n and (_is_ident_char(source[j]) or (source[j] == "." and j + 1 < n and _is_ident_start(source[j + 1]))):
				j += 1
			_tokens.append(["id", source.substr(i, j - i)])
			i = j
		elif c in "+-*/%^(),":
			_tokens.append(["op", c])
			i += 1
		else:
			error = "caracter no permitido '%s'" % c
			return false
		if _tokens.size() > MAX_NODES * 2:
			error = "formula demasiado compleja"
			return false
	return true


func _peek_op(op: String) -> bool:
	return _pos < _tokens.size() and _tokens[_pos][0] == "op" and _tokens[_pos][1] == op


func _count_node(depth: int) -> bool:
	_nodes += 1
	if _nodes > MAX_NODES:
		error = "formula demasiado compleja (max %d nodos)" % MAX_NODES
		return false
	if depth > MAX_DEPTH:
		error = "formula demasiado anidada (max %d niveles)" % MAX_DEPTH
		return false
	return true


func _parse_expr(depth: int) -> Variant:
	var left: Variant = _parse_term(depth + 1)
	while error == "" and (_peek_op("+") or _peek_op("-")):
		var op: String = _tokens[_pos][1]
		_pos += 1
		var right: Variant = _parse_term(depth + 1)
		if error != "" or not _count_node(depth):
			return null
		left = ["bin", op, left, right]
	return left


func _parse_term(depth: int) -> Variant:
	var left: Variant = _parse_unary(depth + 1)
	while error == "" and (_peek_op("*") or _peek_op("/") or _peek_op("%")):
		var op: String = _tokens[_pos][1]
		_pos += 1
		var right: Variant = _parse_unary(depth + 1)
		if error != "" or not _count_node(depth):
			return null
		left = ["bin", op, left, right]
	return left


func _parse_unary(depth: int) -> Variant:
	if not _count_node(depth):
		return null
	if _peek_op("-"):
		_pos += 1
		var inner: Variant = _parse_unary(depth + 1)
		return ["neg", inner]
	return _parse_power(depth + 1)


func _parse_power(depth: int) -> Variant:
	var base: Variant = _parse_primary(depth + 1)
	if error == "":
		if _peek_op("^"):
			_pos += 1
			var exp: Variant = _parse_unary(depth + 1)
			if error != "" or not _count_node(depth):
				return null
			return ["bin", "^", base, exp]
	return base


func _parse_primary(depth: int) -> Variant:
	if not _count_node(depth):
		return null
	if _pos >= _tokens.size():
		error = "expresion incompleta"
		return null
	var tok: Array = _tokens[_pos]
	if tok[0] == "num":
		_pos += 1
		return ["num", tok[1]]
	if tok[0] == "id":
		_pos += 1
		var name: String = tok[1]
		if _peek_op("("):
			if not FUNCS.has(name):
				error = "funcion desconocida '%s'" % name
				return null
			_pos += 1
			var args: Array = []
			if not _peek_op(")"):
				while true:
					args.append(_parse_expr(depth + 1))
					if error != "":
						return null
					if _peek_op(","):
						_pos += 1
						continue
					break
			if not _peek_op(")"):
				error = "falta ')' en la llamada a '%s'" % name
				return null
			_pos += 1
			var arity: int = FUNCS[name]
			if (arity >= 0 and args.size() != arity) or (arity < 0 and args.size() < 1):
				error = "numero de argumentos invalido para '%s'" % name
				return null
			return ["call", name, args]
		return ["var", name.split(".")]
	if tok[0] == "op" and tok[1] == "(":
		_pos += 1
		var inner: Variant = _parse_expr(depth + 1)
		if error != "":
			return null
		if not _peek_op(")"):
			error = "falta ')'"
			return null
		_pos += 1
		return inner
	error = "token inesperado '%s'" % str(tok[1])
	return null


static func _is_digit(c: String) -> bool:
	return c >= "0" and c <= "9"


static func _is_ident_start(c: String) -> bool:
	return (c >= "a" and c <= "z") or (c >= "A" and c <= "Z") or c == "_"


static func _is_ident_char(c: String) -> bool:
	return _is_ident_start(c) or _is_digit(c)


# --- Evaluacion -------------------------------------------------------------

func _fail(msg: String) -> Dictionary:
	return {"ok": false, "value": 0.0, "error": msg}


func _eval(node: Array, resolver: Callable, depth: int) -> Dictionary:
	match node[0]:
		"num":
			return {"ok": true, "value": float(node[1]), "error": ""}
		"var":
			var r: Variant = resolver.call(node[1])
			if r is Dictionary and r.get("ok", false):
				return {"ok": true, "value": float(r["value"]), "error": ""}
			var msg: String = "variable no resoluble '%s'" % ".".join(node[1])
			if r is Dictionary and r.get("error", "") != "":
				msg = r["error"]
			return _fail(msg)
		"neg":
			var v := _eval(node[1], resolver, depth + 1)
			if not v["ok"]:
				return v
			return {"ok": true, "value": -float(v["value"]), "error": ""}
		"bin":
			var a := _eval(node[2], resolver, depth + 1)
			if not a["ok"]:
				return a
			var b := _eval(node[3], resolver, depth + 1)
			if not b["ok"]:
				return b
			var x: float = a["value"]
			var y: float = b["value"]
			var out: float
			match node[1]:
				"+":
					out = x + y
				"-":
					out = x - y
				"*":
					out = x * y
				"/":
					if y == 0.0:
						return _fail("division entre cero")
					out = x / y
				"%":
					if y == 0.0:
						return _fail("modulo entre cero")
					out = fmod(x, y)
				"^":
					out = pow(x, y)
				_:
					return _fail("operador desconocido")
			if is_nan(out) or is_inf(out):
				return _fail("resultado no finito")
			return {"ok": true, "value": out, "error": ""}
		"call":
			var vals: Array = []
			for arg in node[2]:
				var r2 := _eval(arg, resolver, depth + 1)
				if not r2["ok"]:
					return r2
				vals.append(float(r2["value"]))
			var res: float
			match node[1]:
				"min":
					res = vals[0]
					for v2 in vals:
						res = minf(res, v2)
				"max":
					res = vals[0]
					for v2 in vals:
						res = maxf(res, v2)
				"clamp":
					res = clampf(vals[0], vals[1], vals[2])
				"abs":
					res = absf(vals[0])
				"floor":
					res = floorf(vals[0])
				"ceil":
					res = ceilf(vals[0])
				"round":
					res = roundf(vals[0])
				"sqrt":
					if vals[0] < 0.0:
						return _fail("raiz de numero negativo")
					res = sqrt(vals[0])
				_:
					return _fail("funcion desconocida")
			if is_nan(res) or is_inf(res):
				return _fail("resultado no finito")
			return {"ok": true, "value": res, "error": ""}
	return _fail("nodo invalido")


func _collect(node: Array, out: Array) -> void:
	match node[0]:
		"var":
			out.append(".".join(node[1]))
		"neg":
			_collect(node[1], out)
		"bin":
			_collect(node[2], out)
			_collect(node[3], out)
		"call":
			for a in node[2]:
				_collect(a, out)
