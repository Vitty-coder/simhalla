class_name Rounding
extends RefCounted
## Redondeo configurable y determinista (precision decimal interna confirmada).

const MODES := ["none", "round", "floor", "ceil", "trunc"]


## `mode`: none | round (mitad lejos de cero) | floor | ceil | trunc.
static func apply(value: float, mode: String, decimals: int) -> float:
	if mode == "none":
		return value
	var scale: float = pow(10.0, float(decimals))
	var v: float = value * scale
	match mode:
		"round":
			v = roundf(v)
		"floor":
			v = floorf(v)
		"ceil":
			v = ceilf(v)
		"trunc":
			v = floorf(v) if v >= 0.0 else ceilf(v)
		_:
			return value
	return v / scale
