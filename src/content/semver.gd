class_name SemVer
extends RefCounted
## Versiones semanticas MAJOR.MINOR.PATCH[-prerelease] y restricciones.
##
## Restricciones: "*" (cualquiera), "1.2.3" (exacta), "^1.2.3" (compatible:
## >=1.2.3 y mismo MAJOR; con MAJOR 0, mismo MINOR), "~1.2.3" (>=1.2.3 <1.3.0),
## ">=1.2.3". Una version con prerelease es menor que la misma sin ella.

static var _re: RegEx = null


## Devuelve [major, minor, patch, prerelease] o [] si es invalida.
static func parse(text: String) -> Array:
	if _re == null:
		_re = RegEx.new()
		_re.compile("^(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})\\.(0|[1-9][0-9]{0,8})(?:-([0-9A-Za-z]+(?:\\.[0-9A-Za-z]+)*))?$")
	var m := _re.search(text)
	if m == null:
		return []
	return [int(m.get_string(1)), int(m.get_string(2)), int(m.get_string(3)), m.get_string(4)]


static func is_valid(text: String) -> bool:
	return not parse(text).is_empty()


## -1, 0, 1 (ambas deben ser validas).
static func compare(a: String, b: String) -> int:
	var x := parse(a)
	var y := parse(b)
	for i in 3:
		if x[i] != y[i]:
			return -1 if x[i] < y[i] else 1
	if x[3] == y[3]:
		return 0
	if x[3] == "":
		return 1
	if y[3] == "":
		return -1
	return -1 if x[3] < y[3] else 1


static func is_valid_constraint(text: String) -> bool:
	if text == "*":
		return true
	if text.begins_with(">="):
		return is_valid(text.substr(2))
	if text.begins_with("^") or text.begins_with("~"):
		return is_valid(text.substr(1))
	return is_valid(text)


static func satisfies(version: String, constraint: String) -> bool:
	if not is_valid(version) or not is_valid_constraint(constraint):
		return false
	if constraint == "*":
		return true
	if constraint.begins_with(">="):
		return compare(version, constraint.substr(2)) >= 0
	if constraint.begins_with("^") or constraint.begins_with("~"):
		var base := constraint.substr(1)
		if compare(version, base) < 0:
			return false
		var b := parse(base)
		var v := parse(version)
		if constraint.begins_with("~"):
			return v[0] == b[0] and v[1] == b[1]
		if b[0] > 0:
			return v[0] == b[0]
		return v[0] == 0 and v[1] == b[1]
	return compare(version, constraint) == 0
